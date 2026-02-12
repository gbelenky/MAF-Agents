using Microsoft.Agents.Builder;
using Microsoft.Agents.Builder.Compat;
using Microsoft.Agents.Connector;
using Microsoft.Agents.Core.Models;
using Microsoft.Extensions.Options;
using System.Security.Claims;

namespace OneDriveAgent.Services;

/// <summary>
/// Bot that handles messages from Teams and M365 Copilot.
/// Supports SSO for seamless authentication when admin consent is granted.
/// Falls back to OAuth card when SSO is not available.
/// </summary>
public class OneDriveAgentBot : ActivityHandler
{
    private readonly IMafAgentService _agentService;
    private readonly BotConfig _config;
    private readonly IChannelServiceClientFactory _channelServiceClientFactory;
    private readonly ILogger<OneDriveAgentBot> _logger;

    public OneDriveAgentBot(
        IMafAgentService agentService,
        IOptions<BotConfig> config,
        IChannelServiceClientFactory channelServiceClientFactory,
        ILogger<OneDriveAgentBot> logger)
    {
        _agentService = agentService;
        _config = config.Value;
        _channelServiceClientFactory = channelServiceClientFactory;
        _logger = logger;
        
        // Log config values at startup for debugging
        _logger.LogInformation("Bot initialized with AppId={AppId}, TenantId={TenantId}, OAuthConnection={OAuthConnection}",
            string.IsNullOrEmpty(_config.MicrosoftAppId) ? "[EMPTY]" : _config.MicrosoftAppId[..8] + "...",
            string.IsNullOrEmpty(_config.MicrosoftAppTenantId) ? "[EMPTY]" : _config.MicrosoftAppTenantId[..8] + "...",
            _config.OAuthConnectionName);
    }

    /// <summary>
    /// Handle incoming messages from Teams or M365 Copilot.
    /// With SSO enabled, token is available immediately without user action.
    /// </summary>
    protected override async Task OnMessageActivityAsync(ITurnContext<IMessageActivity> turnContext, CancellationToken cancellationToken)
    {
        var userMessage = turnContext.Activity.Text?.Trim();
        
        _logger.LogDebug("OnMessageActivityAsync called with message: {Message}", userMessage ?? "(empty)");
        
        if (string.IsNullOrWhiteSpace(userMessage))
        {
            await turnContext.SendActivityAsync(MessageFactory.Text("Please send a message."), cancellationToken);
            return;
        }

        _logger.LogDebug("Received message from {UserId}: {Message}", 
            turnContext.Activity.From.Id, userMessage);

        // Check if message is a magic code (6-digit number from OAuth flow)
        // Magic codes are a fallback when SSO fails (e.g., Bot Emulator, Web Test Chat,
        // missing admin consent, older Teams clients). With proper SSO setup in Teams,
        // magic codes are rarely needed, but we keep this for testing and edge cases.
        string? magicCode = null;
        if (System.Text.RegularExpressions.Regex.IsMatch(userMessage, @"^\d{6}$"))
        {
            _logger.LogDebug("Message looks like a magic code: {Code}", userMessage);
            magicCode = userMessage;
        }

        // Try to get the user's token from the OAuth connection
        var tokenResponse = await GetUserTokenAsync(turnContext, magicCode, cancellationToken);

        if (tokenResponse == null)
        {
            _logger.LogDebug("No token found, sending OAuth card");
            // User needs to sign in - send OAuth card
            await SendOAuthCardAsync(turnContext, cancellationToken);
            return;
        }
        
        // If this was a magic code and we got a token, acknowledge sign-in success
        if (magicCode != null)
        {
            _logger.LogDebug("Magic code validated successfully, user is signed in");
            await turnContext.SendActivityAsync(
                MessageFactory.Text("You're now signed in! How can I help you with your OneDrive files?"), 
                cancellationToken);
            return;
        }

        _logger.LogDebug("Token found, processing message");

        try
        {
            // Show typing indicator while processing
            await turnContext.SendActivityAsync(new Activity { Type = ActivityTypes.Typing }, cancellationToken);

            // Call the MAF Agent with the user's token for OBO
            var response = await _agentService.ChatAsync(
                userMessage, 
                tokenResponse.Token, 
                cancellationToken);

            await turnContext.SendActivityAsync(MessageFactory.Text(response), cancellationToken);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error processing message");
            await turnContext.SendActivityAsync(
                MessageFactory.Text("Sorry, I encountered an error processing your request. Please try again."), 
                cancellationToken);
        }
    }

    /// <summary>
    /// Handle sign-in verification from OAuth card.
    /// </summary>
    protected override async Task OnTokenResponseEventAsync(ITurnContext<IEventActivity> turnContext, CancellationToken cancellationToken)
    {
        _logger.LogInformation("Token response event received - user signed in via OAuth card");

        // Token received - the user has signed in
        // Now process any pending message or just acknowledge
        await turnContext.SendActivityAsync(
            MessageFactory.Text("You're now signed in! How can I help you with your OneDrive files?"), 
            cancellationToken);
    }

    /// <summary>
    /// Handle SSO token exchange from Teams.
    /// This is called when Teams sends an SSO token that needs to be exchanged.
    /// </summary>
    protected override async Task<InvokeResponse> OnInvokeActivityAsync(ITurnContext<IInvokeActivity> turnContext, CancellationToken cancellationToken)
    {
        // Handle token exchange for SSO
        if (turnContext.Activity.Name == "signin/tokenExchange")
        {
            _logger.LogInformation("SSO token exchange request received");
            
            // Log the raw activity value to debug SSO issues
            var rawValue = turnContext.Activity.Value?.ToString() ?? "null";
            _logger.LogInformation("Raw Activity.Value: {RawValue}", rawValue);
            if (turnContext.Activity.Value is System.Text.Json.JsonElement jsonDbg)
            {
                _logger.LogInformation("Activity Value JSON: {Json}", jsonDbg.GetRawText());
            }
            
            try
            {
                var tokenExchangeRequest = turnContext.Activity.Value as TokenExchangeInvokeRequest;
                if (tokenExchangeRequest == null)
                {
                    // Try to deserialize from JSON with case-insensitive matching
                    // Teams sends lowercase properties (id, token, connectionName) but TokenExchangeInvokeRequest uses PascalCase
                    if (turnContext.Activity.Value is System.Text.Json.JsonElement jsonElement)
                    {
                        var options = new System.Text.Json.JsonSerializerOptions
                        {
                            PropertyNameCaseInsensitive = true
                        };
                        tokenExchangeRequest = System.Text.Json.JsonSerializer.Deserialize<TokenExchangeInvokeRequest>(
                            jsonElement.GetRawText(), options);
                    }
                }

                if (tokenExchangeRequest != null)
                {
                    _logger.LogInformation("Token exchange request: Id={Id}, TokenPresent={TokenPresent}", 
                        tokenExchangeRequest.Id, 
                        !string.IsNullOrEmpty(tokenExchangeRequest.Token));
                    
                    // Check if the token is actually present
                    if (string.IsNullOrEmpty(tokenExchangeRequest.Token))
                    {
                        _logger.LogWarning("SSO token from Teams is empty - sending manual sign-in card");
                        
                        // SSO failed - send a sign-in card directly to the user
                        await SendManualSignInCardAsync(turnContext, cancellationToken);
                        
                        return new InvokeResponse
                        {
                            Status = 200, // Return success to stop Teams from retrying
                            Body = new TokenExchangeInvokeResponse
                            {
                                Id = tokenExchangeRequest.Id,
                                ConnectionName = _config.OAuthConnectionName,
                                FailureDetail = "SSO not available"
                            }
                        };
                    }
                    
                    var claimsIdentity = GetClaimsIdentity(turnContext);
                    var userTokenClient = await _channelServiceClientFactory.CreateUserTokenClientAsync(
                        claimsIdentity, 
                        cancellationToken);

                    // Exchange the SSO token for an access token
                    var tokenResponse = await userTokenClient.ExchangeTokenAsync(
                        turnContext.Activity.From.Id,
                        _config.OAuthConnectionName,
                        turnContext.Activity.ChannelId,
                        new TokenExchangeRequest { Token = tokenExchangeRequest.Token },
                        cancellationToken);

                    if (!string.IsNullOrEmpty(tokenResponse?.Token))
                    {
                        _logger.LogInformation("SSO token exchange successful");
                        
                        // Return success - no body needed
                        return new InvokeResponse { Status = 200 };
                    }
                }
                
                _logger.LogWarning("SSO token exchange failed - token was null or empty");
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "SSO token exchange failed");
            }

            // Return failure - Teams will fall back to OAuth card
            return new InvokeResponse
            {
                Status = 409, // Conflict - indicates the exchange failed
                Body = new TokenExchangeInvokeResponse
                {
                    Id = turnContext.Activity.Id,
                    ConnectionName = _config.OAuthConnectionName,
                    FailureDetail = "Token exchange failed. User may need to sign in manually."
                }
            };
        }

        // For other invoke activities, use base implementation
        return await base.OnInvokeActivityAsync(turnContext, cancellationToken);
    }

    /// <summary>
    /// Handle new members added to the conversation.
    /// With SSO, no sign-in prompt is needed - just welcome the user.
    /// </summary>
    protected override async Task OnMembersAddedAsync(
        IList<ChannelAccount> membersAdded, 
        ITurnContext<IConversationUpdateActivity> turnContext, 
        CancellationToken cancellationToken)
    {
        foreach (var member in membersAdded)
        {
            if (member.Id != turnContext.Activity.Recipient.Id)
            {
                // With SSO, we don't need to prompt for sign-in
                // The token will be available when the user sends their first message
                await turnContext.SendActivityAsync(
                    MessageFactory.Text("Welcome! I'm the OneDrive Agent. I can help you browse, search, and manage your OneDrive files. Just ask me anything!"), 
                    cancellationToken);
            }
        }
    }

    /// <summary>
    /// Get claims identity for creating token client.
    /// The claims identity must contain the bot's Microsoft App ID to authenticate with the Token Service.
    /// When using UserAssignedMSI, the bot authenticates with MSI but the Token Service
    /// still needs the Bot's App ID (not the MSI client ID) to identify which bot is making the request.
    /// </summary>
    private ClaimsIdentity GetClaimsIdentity(ITurnContext turnContext)
    {
        // Always use the configured Bot App ID, not Recipient.Id (which may be a display name or Teams-formatted ID)
        var botAppId = _config.MicrosoftAppId;
        
        _logger.LogDebug("Creating claims identity with Bot App ID: {BotAppId}", botAppId);
        
        return new ClaimsIdentity(new List<Claim>
        {
            new Claim(ClaimTypes.NameIdentifier, botAppId),
            new Claim("appid", botAppId),
            new Claim("aud", botAppId),
            new Claim("ver", "2.0")
        }, "Bearer");
    }

    /// <summary>
    /// Try to get the user's token from the OAuth connection.
    /// With SSO properly configured, this returns a token immediately without user interaction:
    /// 1. Teams sends SSO token in signin/tokenExchange invoke
    /// 2. We exchange it for access token in OnInvokeActivityAsync
    /// 3. Token is cached, so GetUserTokenAsync returns it immediately
    /// </summary>
    private async Task<Microsoft.Agents.Core.Models.TokenResponse?> GetUserTokenAsync(ITurnContext turnContext, string? magicCode, CancellationToken cancellationToken)
    {
        _logger.LogDebug("GetUserTokenAsync - Starting token retrieval (magicCode={HasMagicCode})", magicCode != null);
        try
        {
            var claimsIdentity = GetClaimsIdentity(turnContext);
            var userTokenClient = await _channelServiceClientFactory.CreateUserTokenClientAsync(
                claimsIdentity, 
                cancellationToken);
            
            _logger.LogDebug("GetUserTokenAsync - Calling GetUserTokenAsync for user {UserId}, connection {Connection}", 
                turnContext.Activity.From.Id, _config.OAuthConnectionName);
                
            var response = await userTokenClient.GetUserTokenAsync(
                turnContext.Activity.From.Id,
                _config.OAuthConnectionName,
                turnContext.Activity.ChannelId,
                magicCode, // Pass magic code if provided
                cancellationToken);

            if (response != null && !string.IsNullOrEmpty(response.Token))
            {
                _logger.LogDebug("GetUserTokenAsync - Token found!");
            }
            else
            {
                _logger.LogDebug("GetUserTokenAsync - No token (response={HasResponse}, token={HasToken})",
                    response != null, response?.Token != null);
            }
            
            return response;
        }
        catch (Exception ex)
        {
            _logger.LogDebug(ex, "GetUserTokenAsync - Exception: {Error}", ex.Message);
            return null;
        }
    }

    /// <summary>
    /// Send an OAuth card to prompt the user to sign in.
    /// This is a fallback when SSO is not available or fails.
    /// </summary>
    private async Task SendOAuthCardAsync(ITurnContext turnContext, CancellationToken cancellationToken)
    {
        _logger.LogDebug("SendOAuthCardAsync - Starting to send OAuth card");
        
        try
        {
            var claimsIdentity = GetClaimsIdentity(turnContext);
            _logger.LogDebug("SendOAuthCardAsync - Got claims identity");
            
            var userTokenClient = await _channelServiceClientFactory.CreateUserTokenClientAsync(
                claimsIdentity, 
                cancellationToken);
            
            _logger.LogDebug("SendOAuthCardAsync - Got user token client");
                
            var signInResource = await userTokenClient.GetSignInResourceAsync(
                _config.OAuthConnectionName,
                turnContext.Activity,
                null, // final redirect
                cancellationToken);
            
            _logger.LogDebug("SendOAuthCardAsync - Got signInResource, TokenExchangeResource: {HasTokenExchange}", 
                signInResource.TokenExchangeResource != null);

            var oauthCard = new OAuthCard
            {
                Text = "Please sign in to access your OneDrive files",
                ConnectionName = _config.OAuthConnectionName,
                Buttons = new List<CardAction>
                {
                    new CardAction
                    {
                        Type = ActionTypes.Signin,
                        Title = "Sign In",
                        Value = signInResource.SignInLink
                    }
                },
                // This is critical for SSO - includes the token exchange resource
                TokenExchangeResource = signInResource.TokenExchangeResource
            };

            var attachment = new Attachment
            {
                ContentType = OAuthCard.ContentType,
                Content = oauthCard
            };

            var reply = MessageFactory.Attachment(attachment);
            await turnContext.SendActivityAsync(reply, cancellationToken);
            _logger.LogDebug("SendOAuthCardAsync - OAuth card sent successfully");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to send OAuth card. AppId={AppId}, Connection={Connection}", 
                _config.MicrosoftAppId, _config.OAuthConnectionName);
            _logger.LogDebug("SendOAuthCardAsync - EXCEPTION: {Error}", ex.Message);
            
            // Include error details to help debug - remove in production
            var errorDetail = ex.InnerException?.Message ?? ex.Message;
            await turnContext.SendActivityAsync(
                MessageFactory.Text($"OAuth error: {errorDetail}"), 
                cancellationToken);
        }
    }

    /// <summary>
    /// Send a manual sign-in card when SSO fails.
    /// This provides a fallback for users when Teams SSO isn't available.
    /// </summary>
    private async Task SendManualSignInCardAsync(ITurnContext turnContext, CancellationToken cancellationToken)
    {
        _logger.LogDebug("SendManualSignInCardAsync - Sending manual sign-in card");
        
        try
        {
            var claimsIdentity = GetClaimsIdentity(turnContext);
            var userTokenClient = await _channelServiceClientFactory.CreateUserTokenClientAsync(
                claimsIdentity, 
                cancellationToken);
                
            var signInResource = await userTokenClient.GetSignInResourceAsync(
                _config.OAuthConnectionName,
                turnContext.Activity,
                null,
                cancellationToken);

            // Create a simple sign-in card without TokenExchangeResource to bypass SSO
            var signInCard = new HeroCard
            {
                Title = "Sign in required",
                Text = "SSO is not available. Please click the button below to sign in with your Microsoft account.",
                Buttons = new List<CardAction>
                {
                    new CardAction
                    {
                        Type = ActionTypes.OpenUrl,
                        Title = "Sign In",
                        Value = signInResource.SignInLink
                    }
                }
            };

            var attachment = new Attachment
            {
                ContentType = HeroCard.ContentType,
                Content = signInCard
            };

            var reply = MessageFactory.Attachment(attachment);
            await turnContext.SendActivityAsync(reply, cancellationToken);
            _logger.LogDebug("SendManualSignInCardAsync - Manual sign-in card sent");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to send manual sign-in card");
            await turnContext.SendActivityAsync(
                MessageFactory.Text("I need you to sign in, but encountered an issue. Please try again later."), 
                cancellationToken);
        }
    }
}
