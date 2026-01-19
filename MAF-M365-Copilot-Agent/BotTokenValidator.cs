using System.IdentityModel.Tokens.Jwt;
using Microsoft.Agents.Authentication;
using Microsoft.Extensions.Logging;
using Microsoft.IdentityModel.Protocols;
using Microsoft.IdentityModel.Protocols.OpenIdConnect;
using Microsoft.IdentityModel.Tokens;
using HttpRequestData = Microsoft.Azure.Functions.Worker.Http.HttpRequestData;

namespace MAFCopilotAgent;

/// <summary>
/// Validates Bot Framework JWT tokens for Azure Functions.
/// Follows the M365 Agents SDK authentication patterns.
/// </summary>
public class BotTokenValidator
{
    private readonly BotAuthConfig _authConfig;
    private readonly ILogger _logger;
    private static ConfigurationManager<OpenIdConnectConfiguration>? _configManager;

    public BotTokenValidator(BotAuthConfig authConfig, ILogger logger)
    {
        _authConfig = authConfig;
        _logger = logger;
    }

    /// <summary>
    /// Validates the Bot Framework JWT token from the Authorization header.
    /// </summary>
    public async Task<AuthValidationResult> ValidateAsync(HttpRequestData req)
    {
        if (!_authConfig.IsAuthEnabled)
        {
            _logger.LogInformation("Authentication skipped (local development mode)");
            return AuthValidationResult.Success("local-dev");
        }

        try
        {
            var token = ExtractBearerToken(req);
            if (token == null)
            {
                return AuthValidationResult.Failure("Missing or invalid Authorization header");
            }

            var openIdConfig = await GetOpenIdConfigurationAsync();
            var validationParameters = BuildValidationParameters(openIdConfig);

            var tokenHandler = new JwtSecurityTokenHandler();
            var principal = tokenHandler.ValidateToken(token, validationParameters, out _);

            var appId = ExtractAppId(principal);
            _logger.LogInformation("Authentication successful for AppId: {AppId}", appId);
            
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

    private static string? ExtractBearerToken(HttpRequestData req)
    {
        if (!req.Headers.TryGetValues("Authorization", out var authHeaders))
            return null;

        var authHeader = authHeaders.FirstOrDefault();
        if (string.IsNullOrEmpty(authHeader) || !authHeader.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase))
            return null;

        var token = authHeader.Substring("Bearer ".Length).Trim();
        return string.IsNullOrEmpty(token) ? null : token;
    }

    private static async Task<OpenIdConnectConfiguration> GetOpenIdConfigurationAsync()
    {
        _configManager ??= new ConfigurationManager<OpenIdConnectConfiguration>(
            AuthenticationConstants.PublicAzureBotServiceOpenIdMetadataUrl,
            new OpenIdConnectConfigurationRetriever(),
            new HttpDocumentRetriever());

        return await _configManager.GetConfigurationAsync(CancellationToken.None);
    }

    private TokenValidationParameters BuildValidationParameters(OpenIdConnectConfiguration openIdConfig)
    {
        return new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidIssuers = GetValidIssuers(),
            ValidateAudience = true,
            ValidAudiences = new[] { _authConfig.MicrosoftAppId },
            ValidateLifetime = true,
            IssuerSigningKeys = openIdConfig.SigningKeys,
            ClockSkew = TimeSpan.FromMinutes(5)
        };
    }

    private string[] GetValidIssuers()
    {
        var issuers = new List<string>
        {
            AuthenticationConstants.BotFrameworkTokenIssuer,
            // Bot Framework tenant
            string.Format(AuthenticationConstants.ValidTokenIssuerUrlTemplateV1, "d6d49420-f39b-4df7-a1dc-d59a935871db"),
            string.Format(AuthenticationConstants.ValidTokenIssuerUrlTemplateV2, "d6d49420-f39b-4df7-a1dc-d59a935871db"),
            // US Gov tenant
            string.Format(AuthenticationConstants.ValidTokenIssuerUrlTemplateV1, "f8cdef31-a31e-4b4a-93e4-5f571e91255a"),
            string.Format(AuthenticationConstants.ValidTokenIssuerUrlTemplateV2, "f8cdef31-a31e-4b4a-93e4-5f571e91255a")
        };

        // Add custom tenant if configured
        if (!string.IsNullOrEmpty(_authConfig.MicrosoftAppTenantId))
        {
            issuers.Add(string.Format(AuthenticationConstants.ValidTokenIssuerUrlTemplateV1, _authConfig.MicrosoftAppTenantId));
            issuers.Add(string.Format(AuthenticationConstants.ValidTokenIssuerUrlTemplateV2, _authConfig.MicrosoftAppTenantId));
        }

        return issuers.ToArray();
    }

    private static string ExtractAppId(System.Security.Claims.ClaimsPrincipal principal)
    {
        var appIdClaim = principal.FindFirst("appid") ?? principal.FindFirst("azp");
        return appIdClaim?.Value ?? "unknown";
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

    public bool IsAuthEnabled => !string.IsNullOrEmpty(MicrosoftAppId);
}

/// <summary>
/// Result of token validation.
/// </summary>
public class AuthValidationResult
{
    public bool IsValid { get; set; }
    public string? AppId { get; set; }
    public string? Reason { get; set; }

    public static AuthValidationResult Success(string appId) => new() { IsValid = true, AppId = appId };
    public static AuthValidationResult Failure(string reason) => new() { IsValid = false, Reason = reason };
}
