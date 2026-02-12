// Copyright (c) Microsoft. All rights reserved.

using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using Azure.Identity;

namespace OneDriveAgent.Setup;

/// <summary>
/// Setup tool to create Agent Identity Blueprint and Agent Identity
/// using Microsoft Graph API (Entra ID).
/// </summary>
public class AgentIdentitySetup
{
    private const string GraphApiBase = "https://graph.microsoft.com/v1.0";
    private const string GraphBetaBase = "https://graph.microsoft.com/beta";
    
    private readonly HttpClient _httpClient;
    private readonly string _tenantId;

    public AgentIdentitySetup(string tenantId)
    {
        _tenantId = tenantId;
        _httpClient = new HttpClient();
    }

    /// <summary>
    /// Run the complete setup to create Agent Identity Blueprint and Agent Identity.
    /// </summary>
    public async Task<SetupResult> RunSetupAsync(string blueprintName, string agentIdentityName, CancellationToken cancellationToken = default)
    {
        Console.WriteLine("=== Agent Identity Setup ===");
        Console.WriteLine($"Tenant: {_tenantId}");
        Console.WriteLine();

        // Get token for Graph API
        Console.WriteLine("Authenticating with Azure CLI credential...");
        var credential = new AzureCliCredential();
        var token = await credential.GetTokenAsync(
            new Azure.Core.TokenRequestContext(["https://graph.microsoft.com/.default"]),
            cancellationToken);
        _httpClient.DefaultRequestHeaders.Authorization = 
            new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", token.Token);

        var result = new SetupResult();

        // Step 1: Create Agent Identity Blueprint (Parent App)
        Console.WriteLine($"\n1. Creating Agent Identity Blueprint: {blueprintName}");
        var blueprint = await CreateApplicationAsync(blueprintName, isBlueprint: true, cancellationToken);
        result.BlueprintAppId = blueprint.AppId;
        result.BlueprintObjectId = blueprint.Id;
        Console.WriteLine($"   ✓ Created: {blueprint.AppId}");

        // Step 2: Create Agent Identity (Child App)
        Console.WriteLine($"\n2. Creating Agent Identity: {agentIdentityName}");
        var agentIdentity = await CreateApplicationAsync(agentIdentityName, isBlueprint: false, cancellationToken);
        result.AgentIdentityAppId = agentIdentity.AppId;
        result.AgentIdentityObjectId = agentIdentity.Id;
        Console.WriteLine($"   ✓ Created: {agentIdentity.AppId}");

        // Step 3: Add Graph API permissions to Agent Identity
        Console.WriteLine("\n3. Adding Microsoft Graph API permissions...");
        await AddGraphPermissionsAsync(agentIdentity.Id, cancellationToken);
        Console.WriteLine("   ✓ Added Files.Read and User.Read delegated permissions");

        // Step 4: Create Service Principal for Blueprint
        Console.WriteLine("\n4. Creating Service Principal for Blueprint...");
        var blueprintSp = await CreateServicePrincipalAsync(blueprint.AppId, cancellationToken);
        Console.WriteLine($"   ✓ Service Principal created: {blueprintSp.Id}");

        // Step 5: Create Service Principal for Agent Identity
        Console.WriteLine("\n5. Creating Service Principal for Agent Identity...");
        var agentSp = await CreateServicePrincipalAsync(agentIdentity.AppId, cancellationToken);
        Console.WriteLine($"   ✓ Service Principal created: {agentSp.Id}");

        // Step 6: Expose API on Blueprint (for OBO)
        Console.WriteLine("\n6. Configuring API exposure on Blueprint...");
        await ExposeApiAsync(blueprint.Id, blueprint.AppId, cancellationToken);
        Console.WriteLine("   ✓ API URI and access_as_user scope configured");

        Console.WriteLine("\n=== Setup Complete ===");
        Console.WriteLine("\nConfiguration values for appsettings.json:");
        Console.WriteLine($"  AgentBlueprintClientId: {result.BlueprintAppId}");
        Console.WriteLine($"  AgentIdentityClientId: {result.AgentIdentityAppId}");
        Console.WriteLine($"  TenantId: {_tenantId}");
        Console.WriteLine("\nNOTE: You still need to:");
        Console.WriteLine("  1. Create a User Assigned Managed Identity in Azure");
        Console.WriteLine("  2. Add Federated Identity Credential to the Blueprint linking to the Managed Identity");
        Console.WriteLine("  3. Grant admin consent for the Graph API permissions");

        return result;
    }

    /// <summary>
    /// Create an application registration in Entra ID.
    /// </summary>
    private async Task<AppRegistration> CreateApplicationAsync(string displayName, bool isBlueprint, CancellationToken cancellationToken)
    {
        var requestBody = new
        {
            displayName = displayName,
            signInAudience = "AzureADMyOrg",
            // Agent identities don't need redirect URIs
            web = new { redirectUris = Array.Empty<string>() },
            // Required resource access (will be populated separately for agent identity)
            requiredResourceAccess = Array.Empty<object>()
        };

        var response = await _httpClient.PostAsync(
            $"{GraphApiBase}/applications",
            new StringContent(JsonSerializer.Serialize(requestBody), Encoding.UTF8, "application/json"),
            cancellationToken);

        response.EnsureSuccessStatusCode();
        var content = await response.Content.ReadAsStringAsync(cancellationToken);
        return JsonSerializer.Deserialize<AppRegistration>(content)!;
    }

    /// <summary>
    /// Add Microsoft Graph delegated permissions to an application.
    /// </summary>
    private async Task AddGraphPermissionsAsync(string appObjectId, CancellationToken cancellationToken)
    {
        // Microsoft Graph App ID
        const string graphAppId = "00000003-0000-0000-c000-000000000000";
        
        // Permission IDs (delegated)
        const string filesReadId = "10465720-29dd-4523-a11a-6a75c743c9d9"; // Files.Read
        const string userReadId = "e1fe6dd8-ba31-4d61-89e7-88639da4683d";  // User.Read

        var requestBody = new
        {
            requiredResourceAccess = new[]
            {
                new
                {
                    resourceAppId = graphAppId,
                    resourceAccess = new[]
                    {
                        new { id = filesReadId, type = "Scope" },
                        new { id = userReadId, type = "Scope" }
                    }
                }
            }
        };

        var response = await _httpClient.PatchAsync(
            $"{GraphApiBase}/applications/{appObjectId}",
            new StringContent(JsonSerializer.Serialize(requestBody), Encoding.UTF8, "application/json"),
            cancellationToken);

        response.EnsureSuccessStatusCode();
    }

    /// <summary>
    /// Create a service principal for an application.
    /// </summary>
    private async Task<ServicePrincipal> CreateServicePrincipalAsync(string appId, CancellationToken cancellationToken)
    {
        var requestBody = new { appId = appId };

        var response = await _httpClient.PostAsync(
            $"{GraphApiBase}/servicePrincipals",
            new StringContent(JsonSerializer.Serialize(requestBody), Encoding.UTF8, "application/json"),
            cancellationToken);

        // 409 Conflict means it already exists, which is fine
        if (response.StatusCode == System.Net.HttpStatusCode.Conflict)
        {
            // Get existing service principal
            var searchResponse = await _httpClient.GetAsync(
                $"{GraphApiBase}/servicePrincipals?$filter=appId eq '{appId}'",
                cancellationToken);
            searchResponse.EnsureSuccessStatusCode();
            var searchContent = await searchResponse.Content.ReadAsStringAsync(cancellationToken);
            var searchResult = JsonSerializer.Deserialize<ODataCollection<ServicePrincipal>>(searchContent)!;
            return searchResult.Value.First();
        }

        response.EnsureSuccessStatusCode();
        var content = await response.Content.ReadAsStringAsync(cancellationToken);
        return JsonSerializer.Deserialize<ServicePrincipal>(content)!;
    }

    /// <summary>
    /// Expose an API on the application (set Application ID URI and add scope).
    /// </summary>
    private async Task ExposeApiAsync(string appObjectId, string appId, CancellationToken cancellationToken)
    {
        var scopeId = Guid.NewGuid().ToString();
        
        var requestBody = new
        {
            identifierUris = new[] { $"api://{appId}" },
            api = new
            {
                oauth2PermissionScopes = new[]
                {
                    new
                    {
                        id = scopeId,
                        adminConsentDescription = "Allow the agent to access resources on behalf of the user",
                        adminConsentDisplayName = "Access as user",
                        userConsentDescription = "Allow the agent to access resources on your behalf",
                        userConsentDisplayName = "Access as user",
                        isEnabled = true,
                        type = "User",
                        value = "access_as_user"
                    }
                }
            }
        };

        var response = await _httpClient.PatchAsync(
            $"{GraphApiBase}/applications/{appObjectId}",
            new StringContent(JsonSerializer.Serialize(requestBody), Encoding.UTF8, "application/json"),
            cancellationToken);

        response.EnsureSuccessStatusCode();
    }

    /// <summary>
    /// Add a Federated Identity Credential to link Managed Identity.
    /// </summary>
    public async Task AddFederatedCredentialAsync(
        string blueprintObjectId, 
        string managedIdentityClientId,
        string credentialName,
        CancellationToken cancellationToken = default)
    {
        Console.WriteLine($"\nAdding Federated Identity Credential: {credentialName}");

        // Get token
        var credential = new AzureCliCredential();
        var token = await credential.GetTokenAsync(
            new Azure.Core.TokenRequestContext(["https://graph.microsoft.com/.default"]),
            cancellationToken);
        _httpClient.DefaultRequestHeaders.Authorization = 
            new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", token.Token);

        var requestBody = new
        {
            name = credentialName,
            issuer = $"https://login.microsoftonline.com/{_tenantId}/v2.0",
            subject = managedIdentityClientId,
            audiences = new[] { "api://AzureADTokenExchange" },
            description = "Federated credential for Agent Identity using Managed Identity"
        };

        var response = await _httpClient.PostAsync(
            $"{GraphApiBase}/applications/{blueprintObjectId}/federatedIdentityCredentials",
            new StringContent(JsonSerializer.Serialize(requestBody), Encoding.UTF8, "application/json"),
            cancellationToken);

        response.EnsureSuccessStatusCode();
        Console.WriteLine("   ✓ Federated Identity Credential created");
    }
}

public class SetupResult
{
    public string BlueprintAppId { get; set; } = "";
    public string BlueprintObjectId { get; set; } = "";
    public string AgentIdentityAppId { get; set; } = "";
    public string AgentIdentityObjectId { get; set; } = "";
}

public class AppRegistration
{
    [JsonPropertyName("id")]
    public string Id { get; set; } = "";
    
    [JsonPropertyName("appId")]
    public string AppId { get; set; } = "";
    
    [JsonPropertyName("displayName")]
    public string DisplayName { get; set; } = "";
}

public class ServicePrincipal
{
    [JsonPropertyName("id")]
    public string Id { get; set; } = "";
    
    [JsonPropertyName("appId")]
    public string AppId { get; set; } = "";
}

public class ODataCollection<T>
{
    [JsonPropertyName("value")]
    public List<T> Value { get; set; } = new();
}
