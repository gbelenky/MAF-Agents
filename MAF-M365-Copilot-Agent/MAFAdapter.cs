using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.Agents.Authentication;
using Microsoft.Agents.Core.Models;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.AI;
using Microsoft.Extensions.Logging;
using Microsoft.IdentityModel.Protocols;
using Microsoft.IdentityModel.Protocols.OpenIdConnect;
using Microsoft.IdentityModel.Tokens;
using HttpRequestData = Microsoft.Azure.Functions.Worker.Http.HttpRequestData;

namespace MAFCopilotAgent;

/// <summary>
/// MAF Adapter - bridges Bot Framework/Agents Playground protocol to MAF AIAgent.
/// Exposes /api/messages endpoint and invokes the IChatClient directly (no HTTP).
/// Uses proactive messaging to send replies back to serviceUrl.
/// </summary>
public class MAFAdapter
{
    private readonly ILogger<MAFAdapter> _logger;
    private readonly HttpClient _httpClient;
    private readonly IChatClient _chatClient;
    private readonly AIFunction[] _tools;
    private readonly string _systemInstructions;
    private readonly BotAuthConfig _authConfig;
    private static ConfigurationManager<OpenIdConnectConfiguration>? _configManager;

    public MAFAdapter(
        ILogger<MAFAdapter> logger, 
        IHttpClientFactory httpClientFactory, 
        IChatClient chatClient,
        AIFunction[] tools,
        string systemInstructions,
        BotAuthConfig authConfig)
    {
        _logger = logger;
        _httpClient = httpClientFactory.CreateClient();
        _chatClient = chatClient;
        _tools = tools;
        _systemInstructions = systemInstructions;
        _authConfig = authConfig;
    }

    [Function("Messages")]
    public async Task<HttpResponseData> Run(
        [HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "messages")] HttpRequestData req)
    {
        _logger.LogInformation("Received message at /api/messages");

        // Validate Bot Framework authentication (skip in local dev when AppId is not configured)
        if (_authConfig.IsAuthEnabled)
        {
            var authResult = await ValidateBotTokenAsync(req);
            if (!authResult.IsValid)
            {
                _logger.LogWarning("Authentication failed: {Reason}", authResult.Reason);
                var unauthorizedResponse = req.CreateResponse(HttpStatusCode.Unauthorized);
                await unauthorizedResponse.WriteStringAsync(authResult.Reason ?? "Unauthorized");
                return unauthorizedResponse;
            }
            _logger.LogInformation("Authentication successful for AppId: {AppId}", authResult.AppId);
        }
        else
        {
            _logger.LogInformation("Authentication skipped (local development mode)");
        }

        // Parse the Bot Framework activity using M365 Agents SDK Activity model
        var requestBody = await req.ReadAsStringAsync();
        var activity = JsonSerializer.Deserialize<Activity>(requestBody ?? "", new JsonSerializerOptions 
        { 
            PropertyNameCaseInsensitive = true 
        });

        if (activity == null)
        {
            var badResponse = req.CreateResponse(HttpStatusCode.BadRequest);
            await badResponse.WriteStringAsync("Invalid activity");
            return badResponse;
        }

        _logger.LogInformation("Activity type: {Type}, Text: {Text}, ServiceUrl: {ServiceUrl}", 
            activity.Type, activity.Text, activity.ServiceUrl);

        // Handle message activities
        if (activity.Type == ActivityTypes.Message && !string.IsNullOrEmpty(activity.Text))
        {
            var conversationId = activity.Conversation?.Id ?? Guid.NewGuid().ToString();

            try
            {
                _logger.LogInformation("Invoking IChatClient directly for conversation {ConversationId}", conversationId);

                // Build chat messages with system instructions
                var messages = new List<ChatMessage>
                {
                    new ChatMessage(ChatRole.System, _systemInstructions),
                    new ChatMessage(ChatRole.User, activity.Text)
                };

                // Create chat options with tools
                var options = new ChatOptions
                {
                    Tools = _tools.Cast<AITool>().ToList()
                };

                // Call the IChatClient directly (no HTTP round-trip)
                var response = await _chatClient.GetResponseAsync(messages, options);
                var responseText = response.Text ?? "No response from agent";
                
                _logger.LogInformation("IChatClient response: {Response}", responseText);

                // Send reply back to serviceUrl (proactive messaging)
                await SendReplyToServiceUrl(activity, responseText);

                // Return 200 OK to acknowledge receipt
                return req.CreateResponse(HttpStatusCode.OK);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error processing message");
                await SendReplyToServiceUrl(activity, $"Sorry, an error occurred: {ex.Message}");
                return req.CreateResponse(HttpStatusCode.OK);
            }
        }

        // For conversationUpdate - send welcome message
        if (activity.Type == ActivityTypes.ConversationUpdate && activity.MembersAdded != null)
        {
            // Check if bot was added (not user)
            foreach (var member in activity.MembersAdded)
            {
                if (member.Id != activity.Recipient?.Id)
                {
                    await SendReplyToServiceUrl(activity, 
                        "Hello! 👋 I'm your AI assistant powered by Microsoft Agent Framework with Durable Task Scheduler. How can I help you today?");
                    break;
                }
            }
        }

        // Return 200 OK for all activities
        return req.CreateResponse(HttpStatusCode.OK);
    }

    private async Task SendReplyToServiceUrl(Activity activity, string text)
    {
        if (string.IsNullOrEmpty(activity.ServiceUrl) || activity.Conversation == null)
        {
            _logger.LogWarning("Cannot send reply - missing serviceUrl or conversation");
            return;
        }

        // Build a reply activity using M365 Agents SDK Activity model
        var replyActivity = new Activity
        {
            Type = ActivityTypes.Message,
            Text = text,
            From = new ChannelAccount
            {
                Id = activity.Recipient?.Id ?? "bot",
                Name = activity.Recipient?.Name ?? "MAF Durable Agent"
            },
            Conversation = new ConversationAccount
            {
                Id = activity.Conversation.Id
            },
            Recipient = new ChannelAccount
            {
                Id = activity.From?.Id,
                Name = activity.From?.Name
            },
            ReplyToId = activity.Id,
            ServiceUrl = activity.ServiceUrl,
            ChannelId = activity.ChannelId ?? Channels.Webchat
        };

        // Build the reply URL: serviceUrl + /v3/conversations/{conversationId}/activities
        var replyUrl = $"{activity.ServiceUrl.TrimEnd('/')}/v3/conversations/{activity.Conversation.Id}/activities";
        
        _logger.LogInformation("Sending reply to: {ReplyUrl}", replyUrl);

        try
        {
            // Get Bot Framework access token for outbound calls
            var accessToken = await GetBotFrameworkTokenAsync();
            
            // Serialize with proper options
            var jsonOptions = new JsonSerializerOptions
            {
                PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
                DefaultIgnoreCondition = System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingNull
            };
            var jsonContent = JsonSerializer.Serialize(replyActivity, jsonOptions);
            _logger.LogInformation("Sending activity: {Json}", jsonContent);
            
            var request = new HttpRequestMessage(HttpMethod.Post, replyUrl);
            request.Content = new StringContent(jsonContent, System.Text.Encoding.UTF8, "application/json");
            
            if (!string.IsNullOrEmpty(accessToken))
            {
                request.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", accessToken);
            }
            
            var response = await _httpClient.SendAsync(request);
            if (response.IsSuccessStatusCode)
            {
                _logger.LogInformation("Reply sent successfully");
            }
            else
            {
                var error = await response.Content.ReadAsStringAsync();
                _logger.LogError("Failed to send reply: {StatusCode} - {Error}", response.StatusCode, error);
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Exception sending reply to serviceUrl");
        }
    }

    /// <summary>
    /// Acquires an access token for the Bot Framework API using client credentials.
    /// </summary>
    private async Task<string?> GetBotFrameworkTokenAsync()
    {
        if (!_authConfig.IsAuthEnabled || string.IsNullOrEmpty(_authConfig.MicrosoftAppPassword))
        {
            _logger.LogDebug("Skipping token acquisition - auth not enabled or no password configured");
            return null;
        }

        try
        {
            // Use the app's tenant for token acquisition
            // For multi-tenant apps, use the app's home tenant
            var tenantId = _authConfig.MicrosoftAppTenantId ?? "botframework.com";
            var tokenEndpoint = $"https://login.microsoftonline.com/{tenantId}/oauth2/v2.0/token";
            
            _logger.LogDebug("Acquiring token from: {Endpoint}", tokenEndpoint);
            
            var tokenRequest = new Dictionary<string, string>
            {
                ["grant_type"] = "client_credentials",
                ["client_id"] = _authConfig.MicrosoftAppId!,
                ["client_secret"] = _authConfig.MicrosoftAppPassword,
                ["scope"] = "https://api.botframework.com/.default"
            };

            var response = await _httpClient.PostAsync(tokenEndpoint, new FormUrlEncodedContent(tokenRequest));
            
            if (response.IsSuccessStatusCode)
            {
                var tokenResponse = await response.Content.ReadFromJsonAsync<TokenResponse>();
                _logger.LogDebug("Successfully acquired Bot Framework token");
                return tokenResponse?.AccessToken;
            }
            else
            {
                var error = await response.Content.ReadAsStringAsync();
                _logger.LogError("Failed to acquire Bot Framework token: {StatusCode} - {Error}", response.StatusCode, error);
                return null;
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Exception acquiring Bot Framework token");
            return null;
        }
    }

    private class TokenResponse
    {
        [System.Text.Json.Serialization.JsonPropertyName("access_token")]
        public string? AccessToken { get; set; }
        
        [System.Text.Json.Serialization.JsonPropertyName("token_type")]
        public string? TokenType { get; set; }
        
        [System.Text.Json.Serialization.JsonPropertyName("expires_in")]
        public int ExpiresIn { get; set; }
    }

    /// <summary>
    /// Validates the Bot Framework JWT token from the Authorization header.
    /// Supports both Bot Connector and Emulator tokens.
    /// </summary>
    private async Task<AuthValidationResult> ValidateBotTokenAsync(HttpRequestData req)
    {
        try
        {
            // Get Authorization header
            if (!req.Headers.TryGetValues("Authorization", out var authHeaders))
            {
                return AuthValidationResult.Failure("Missing Authorization header");
            }

            var authHeader = authHeaders.FirstOrDefault();
            if (string.IsNullOrEmpty(authHeader) || !authHeader.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase))
            {
                return AuthValidationResult.Failure("Invalid Authorization header format");
            }

            var token = authHeader.Substring("Bearer ".Length).Trim();
            if (string.IsNullOrEmpty(token))
            {
                return AuthValidationResult.Failure("Empty bearer token");
            }

            // Initialize OIDC configuration manager (cached) using SDK constants
            _configManager ??= new ConfigurationManager<OpenIdConnectConfiguration>(
                AuthenticationConstants.PublicAzureBotServiceOpenIdMetadataUrl,
                new OpenIdConnectConfigurationRetriever(),
                new HttpDocumentRetriever());

            var openIdConfig = await _configManager.GetConfigurationAsync(CancellationToken.None);

            // Token validation parameters using SDK constants
            var validationParameters = new TokenValidationParameters
            {
                ValidateIssuer = true,
                ValidIssuers = new[]
                {
                    AuthenticationConstants.BotFrameworkTokenIssuer,
                    string.Format(AuthenticationConstants.ValidTokenIssuerUrlTemplateV1, "d6d49420-f39b-4df7-a1dc-d59a935871db"), // Bot Framework tenant
                    string.Format(AuthenticationConstants.ValidTokenIssuerUrlTemplateV1, "f8cdef31-a31e-4b4a-93e4-5f571e91255a"), // US Gov
                    string.Format(AuthenticationConstants.ValidTokenIssuerUrlTemplateV1, _authConfig.MicrosoftAppTenantId), // Custom tenant V1
                    string.Format(AuthenticationConstants.ValidTokenIssuerUrlTemplateV2, _authConfig.MicrosoftAppTenantId)  // Custom tenant V2
                },
                ValidateAudience = true,
                ValidAudiences = new[] { _authConfig.MicrosoftAppId },
                ValidateLifetime = true,
                IssuerSigningKeys = openIdConfig.SigningKeys,
                ClockSkew = TimeSpan.FromMinutes(5)
            };

            var tokenHandler = new JwtSecurityTokenHandler();
            var principal = tokenHandler.ValidateToken(token, validationParameters, out var validatedToken);

            // Extract the AppId from the token
            var appIdClaim = principal.FindFirst("appid") ?? principal.FindFirst("azp");
            var appId = appIdClaim?.Value ?? "unknown";

            return AuthValidationResult.Success(appId);
        }
        catch (SecurityTokenValidationException ex)
        {
            _logger.LogWarning(ex, "Token validation failed");
            return AuthValidationResult.Failure($"Token validation failed: {ex.Message}");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Unexpected error during token validation");
            return AuthValidationResult.Failure("Authentication error");
        }
    }
}

/// <summary>
/// Bot Framework authentication configuration.
/// When MicrosoftAppId is empty/null, authentication is disabled (local development).
/// </summary>
public class BotAuthConfig
{
    public string? MicrosoftAppId { get; set; }
    public string? MicrosoftAppPassword { get; set; }
    public string? MicrosoftAppTenantId { get; set; }
    
    /// <summary>
    /// Authentication is enabled when MicrosoftAppId is configured.
    /// </summary>
    public bool IsAuthEnabled => !string.IsNullOrEmpty(MicrosoftAppId);
}

public class AuthValidationResult
{
    public bool IsValid { get; set; }
    public string? AppId { get; set; }
    public string? Reason { get; set; }
    
    public static AuthValidationResult Success(string appId) => new() { IsValid = true, AppId = appId };
    public static AuthValidationResult Failure(string reason) => new() { IsValid = false, Reason = reason };
}
