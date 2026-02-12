// Copyright (c) Microsoft. All rights reserved.

using OneDriveAgent.Setup;

/// <summary>
/// CLI tool to set up Agent Identity Blueprint and Agent Identity in Entra ID.
/// 
/// Usage:
///   dotnet run --project OneDriveAgent.csproj -- setup --tenant-id {tenantId}
///   
/// This creates:
///   1. Agent Identity Blueprint (parent app registration)
///   2. Agent Identity (child app registration) 
///   3. Configures API permissions and scopes
///   4. Creates service principals
/// </summary>
public class SetupProgram
{
    public static async Task<int> RunSetupAsync(string[] args)
    {
        // Parse arguments
        string? tenantId = null;
        string blueprintName = "OneDrive-Agent-Blueprint";
        string agentName = "OneDrive-Agent-Identity";
        string? managedIdentityClientId = null;
        string? blueprintObjectId = null;

        for (int i = 0; i < args.Length; i++)
        {
            switch (args[i])
            {
                case "--tenant-id":
                    tenantId = args[++i];
                    break;
                case "--blueprint-name":
                    blueprintName = args[++i];
                    break;
                case "--agent-name":
                    agentName = args[++i];
                    break;
                case "--add-fic":
                    // For adding federated credential after managed identity is created
                    managedIdentityClientId = args[++i];
                    break;
                case "--blueprint-object-id":
                    blueprintObjectId = args[++i];
                    break;
            }
        }

        if (string.IsNullOrEmpty(tenantId))
        {
            Console.WriteLine("Usage:");
            Console.WriteLine("  Setup Agent Identity:");
            Console.WriteLine("    dotnet run -- setup --tenant-id <tenant-id> [--blueprint-name <name>] [--agent-name <name>]");
            Console.WriteLine();
            Console.WriteLine("  Add Federated Identity Credential (after creating Managed Identity):");
            Console.WriteLine("    dotnet run -- setup --tenant-id <tenant-id> --blueprint-object-id <object-id> --add-fic <managed-identity-client-id>");
            return 1;
        }

        var setup = new AgentIdentitySetup(tenantId);

        try
        {
            if (!string.IsNullOrEmpty(managedIdentityClientId) && !string.IsNullOrEmpty(blueprintObjectId))
            {
                // Just add FIC
                await setup.AddFederatedCredentialAsync(blueprintObjectId, managedIdentityClientId, "mi-fic");
            }
            else
            {
                // Run full setup
                var result = await setup.RunSetupAsync(blueprintName, agentName);
                
                // Output JSON for easy copy
                Console.WriteLine("\n--- JSON Configuration ---");
                Console.WriteLine("{");
                Console.WriteLine($"  \"AgentObo\": {{");
                Console.WriteLine($"    \"TenantId\": \"{tenantId}\",");
                Console.WriteLine($"    \"AgentBlueprintClientId\": \"{result.BlueprintAppId}\",");
                Console.WriteLine($"    \"AgentIdentityClientId\": \"{result.AgentIdentityAppId}\",");
                Console.WriteLine($"    \"ManagedIdentityClientId\": \"<create-managed-identity-and-paste-client-id>\",");
                Console.WriteLine($"    \"TargetScope\": \"https://graph.microsoft.com/.default\"");
                Console.WriteLine($"  }}");
                Console.WriteLine("}");
                Console.WriteLine("\nBlueprint Object ID (for adding FIC later): " + result.BlueprintObjectId);
            }
            
            return 0;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"\nError: {ex.Message}");
            if (ex.InnerException != null)
                Console.WriteLine($"Details: {ex.InnerException.Message}");
            return 1;
        }
    }
}
