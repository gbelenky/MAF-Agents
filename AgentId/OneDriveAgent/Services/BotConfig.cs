namespace OneDriveAgent.Services;

/// <summary>
/// Configuration for Azure Bot Service and OAuth/SSO.
/// 
/// SSO Configuration Requirements:
/// 1. Azure Bot Service → OAuth Connection Settings:
///    - Enable "Token Exchange URL" with api://botid-{MicrosoftAppId}
///    - Set scopes: Files.Read Files.ReadWrite User.Read
/// 
/// 2. App Registration → Expose an API:
///    - Application ID URI: api://botid-{MicrosoftAppId}
///    - Add scope: access_as_user
///    - Pre-authorized client apps (8 total):
///      Teams/Office clients:
///      * 1fec8e78-bce4-4aaf-ab1b-5451cc387264 (Teams desktop/mobile)
///      * 5e3ce6c0-2b1f-4285-8d4b-75ee78787346 (Teams web)
///      * d3590ed6-52b3-4102-aeff-aad2292ab01c (Teams general)
///      * 27922004-5251-4030-b22d-91ecd9a37ea4 (Outlook desktop)
///      * bc59ab01-8403-45c6-8796-ac3ef710b3e3 (Teams web alt)
///      * 0ec893e0-5785-4de6-99da-4ed124e5296c (Teams admin)
///      * 4765445b-32c6-49b0-83e6-1d93765276ca (Office)
///      Development/Testing:
///      * ab3be6b7-f5df-413d-ac2d-abf1e3fd9c0b (Agents Playground)
/// 
/// 3. Admin Consent:
///    - Grant admin consent for the tenant for seamless SSO
/// </summary>
public class BotConfig
{
    /// <summary>
    /// The Bot's Microsoft App ID (from Azure Bot Service registration).
    /// Also used for SSO: api://botid-{MicrosoftAppId}
    /// </summary>
    public string MicrosoftAppId { get; set; } = string.Empty;

    /// <summary>
    /// The Bot's app password/secret (not used with Managed Identity).
    /// </summary>
    public string MicrosoftAppPassword { get; set; } = string.Empty;

    /// <summary>
    /// The tenant ID for single-tenant bots.
    /// </summary>
    public string MicrosoftAppTenantId { get; set; } = string.Empty;

    /// <summary>
    /// The OAuth connection name configured in Azure Bot Service.
    /// This connection provides the user's token for OBO.
    /// Must have Token Exchange URL configured for SSO to work.
    /// </summary>
    public string OAuthConnectionName { get; set; } = "graph-connection";
}
