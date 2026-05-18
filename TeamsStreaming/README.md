# Teams Streaming Bot with Microsoft Agent Framework

A Microsoft Teams bot that demonstrates **real-time streaming responses** using the **Microsoft Agent Framework (MAF)** and **M365 Agents SDK**.

## Features

- 🚀 **Real-Time Token Streaming**: See AI responses generate word-by-word in real-time
- 🧠 **Reasoning Output**: Model shows its thought process before answering
- 🤖 **Microsoft Agent Framework**: Uses MAF for AI agent capabilities
- 💬 **Teams Integration**: Full integration with Microsoft Teams via M365 Agents SDK
- ☁️ **Azure OpenAI with Managed Identity**: Secure, keyless authentication using RBAC
- 📊 **Application Insights**: Built-in telemetry and monitoring
- 📦 **Infrastructure as Code**: Complete Bicep templates for Azure deployment via `azd`

## Architecture

```
┌─────────────────┐      ┌──────────────────┐      ┌──────────────────┐
│  Microsoft      │      │  Azure Bot       │      │  Azure App       │
│  Teams          │◄────►│  Service         │◄────►│  Service         │
│                 │      │  (SingleTenant)  │      │  (Managed ID)    │
└─────────────────┘      └──────────────────┘      └─────────┬────────┘
                                                             │
                         ┌──────────────────┐                │
                         │  Application     │◄───────────────┤
                         │  Insights        │                │
                         └──────────────────┘                │
                                                             ▼
                                                   ┌──────────────────┐
                                                   │  Azure OpenAI    │
                                                   │  (RBAC Access)   │
                                                   └──────────────────┘
```

## Prerequisites

- [.NET 8.0 SDK](https://dotnet.microsoft.com/download/dotnet/8.0)
- [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli)
- [Azure Developer CLI (azd)](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd)
- [Azure Subscription](https://azure.microsoft.com/free/)
- Azure OpenAI resource with a deployed model (e.g., gpt-4.1-mini)

### Key NuGet Packages

| Package | Purpose |
|---------|---------|
| `Microsoft.Agents.AI` | Microsoft Agent Framework (MAF) |
| `Microsoft.Agents.Hosting.AspNetCore` | M365 Agents SDK hosting |
| `Microsoft.Agents.Authentication.Msal` | MSAL authentication for Bot Framework |
| `Azure.AI.OpenAI` | Azure OpenAI client |
| `Azure.Identity` | DefaultAzureCredential for managed identity |
| `Microsoft.ApplicationInsights.AspNetCore` | Telemetry and monitoring |

## Deployment

This deployment requires coordination between **Developer** and **Entra Admin** roles.

```
┌── DEVELOPER ──────────────────────────────────────────────────────┐
│  STEP 0: Choose environment name (e.g., mafstreaming)             │
│          ↳ Tell Admin the name                                    │
└───────────────────────────────────────────────────────────────────┘
                              ↓
┌── ENTRA ADMIN ────────────────────────────────────────────────────┐
│  STEP 1: bash scripts/01-create-app-registration.sh --name {name} │
│          ↳ Creates SingleTenant app + Service Principal           │
│          ↳ Output: bot-credentials-{name}.txt                     │
│          ↳ Send file to Developer (securely)                      │
└───────────────────────────────────────────────────────────────────┘
                              ↓
┌── DEVELOPER ──────────────────────────────────────────────────────┐
│  STEP 2: azd env new {name}                                       │
│          azd env set BOT_ID "<from-credentials-file>"             │
│          azd env set BOT_PASSWORD "<from-credentials-file>"       │
│          azd env set AZURE_OPENAI_ENDPOINT "https://xxx..."       │
│          azd env set AZURE_OPENAI_DEPLOYMENT_NAME "gpt-4.1-mini"  │
│          azd up                                                   │
│          ↳ Note the App Service Managed Identity Principal ID     │
│          ↳ Send Managed Identity ID to Admin                      │
└───────────────────────────────────────────────────────────────────┘
                              ↓
┌── ENTRA ADMIN ────────────────────────────────────────────────────┐
│  STEP 3: Grant Managed Identity access to Azure OpenAI:           │
│          az role assignment create \                              │
│            --assignee-object-id <managed-identity-principal-id> \ │
│            --assignee-principal-type ServicePrincipal \           │
│            --role "Cognitive Services OpenAI User" \              │
│            --scope <azure-openai-resource-id>                     │
│          ↳ Notify Developer when done                             │
└───────────────────────────────────────────────────────────────────┘
                              ↓
┌── DEVELOPER ──────────────────────────────────────────────────────┐
│  STEP 4: bash scripts/03-teams-manifest.sh                        │
│          ↳ Output: teams-manifest/{Name}.zip                      │
└───────────────────────────────────────────────────────────────────┘
                              ↓
┌── TEAMS ADMIN ────────────────────────────────────────────────────┐
│  STEP 5: Upload teams-manifest/{Name}.zip to Teams Admin Center   │
│          ↳ OR Developer sideloads for testing                     │
└───────────────────────────────────────────────────────────────────┘
```

---

### Step 0: Developer Chooses Name

Developer decides on environment name (e.g., `mafstreaming`) and tells Entra Admin.

### Step 1: Entra Admin Creates App Registration

```bash
bash scripts/01-create-app-registration.sh --name mafstreaming
```

This creates:
- **SingleTenant** app registration (`AzureADMyOrg`)
- **Service Principal** (required for MSAL authentication)
- **Client Secret** (2-year validity)

**Send `bot-credentials-mafstreaming.txt` to Developer (contains secrets!)**

### Step 2: Developer Deploys to Azure

```bash
# Create environment
azd env new mafstreaming

# Set bot credentials (from admin file)
azd env set BOT_ID "<BOT_ID from credentials file>"
azd env set BOT_PASSWORD "<BOT_PASSWORD from credentials file>"

# Set Azure OpenAI configuration
azd env set AZURE_OPENAI_ENDPOINT "https://your-resource.openai.azure.com/"
azd env set AZURE_OPENAI_DEPLOYMENT_NAME "gpt-4.1-mini"

# Deploy to Azure
azd up

# Verify deployment
curl https://app-<unique-id>.azurewebsites.net/health

# Get Managed Identity Principal ID for Admin
az webapp identity show --name app-<unique-id> --resource-group rg-mafstreaming --query principalId -o tsv
```

**Send the Managed Identity Principal ID to Admin** (e.g., `4fc7df4e-8a01-4cd6-91fe-500c8b07a8b9`)

### Step 3: Entra Admin Grants Azure OpenAI Access

> **Important:** Use **PowerShell** or **CMD** for this command. Git Bash on Windows mangles paths starting with `/subscriptions/`.

```powershell
# PowerShell - Grant Cognitive Services OpenAI User role
az role assignment create `
  --assignee-object-id "<managed-identity-principal-id>" `
  --assignee-principal-type ServicePrincipal `
  --role "Cognitive Services OpenAI User" `
  --scope "/subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.CognitiveServices/accounts/<aoai-resource>"
```

Or in **CMD**:
```cmd
az role assignment create --assignee-object-id "<managed-identity-principal-id>" --assignee-principal-type ServicePrincipal --role "Cognitive Services OpenAI User" --scope "/subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.CognitiveServices/accounts/<aoai-resource>"
```

**Notify Developer when complete.**

### Step 4: Developer Generates Teams Manifest

```bash
bash scripts/03-teams-manifest.sh
```

Creates `teams-manifest/Mafstreaming.zip` with manifest and icons.

### Step 5: Install in Teams

**Option A: Teams Admin Center (recommended for org-wide)**
1. Go to [Teams Admin Center](https://admin.teams.microsoft.com)
2. Navigate to **Teams apps** → **Manage apps** → **Upload new app**
3. Upload `teams-manifest/Mafstreaming.zip`

**Option B: Sideload (for testing)**
1. In Teams, go to **Apps** → **Manage your apps** → **Upload a custom app**
2. Select `teams-manifest/Mafstreaming.zip`

> **Note:** After uploading, wait **2-3 minutes** for the bot to fully register before testing.

---

### Handoff Summary

| Step | From | To | Information |
|------|------|------|-------------|
| 0 | Developer | Admin | Environment name |
| 1 | Admin | Developer | `bot-credentials-{name}.txt` (BOT_ID, BOT_PASSWORD) |
| 2 | Developer | Admin | Managed Identity Principal ID |
| 3 | Admin | Developer | Confirmation that RBAC is granted |

> **Security Note:** The credentials file contains secrets. Transfer securely (encrypted email, secure file share, etc.).

---

## Quick Start (Single Admin/Developer)

If you have both Entra Admin and Developer permissions, run all steps yourself:

```bash
# Step 1: Create app registration (requires Entra Admin)
bash scripts/01-create-app-registration.sh --name mafstreaming

# Step 2: Deploy to Azure
azd env new mafstreaming
azd env set BOT_ID "<BOT_ID from bot-credentials file>"
azd env set BOT_PASSWORD "<BOT_PASSWORD from bot-credentials file>"
azd env set AZURE_OPENAI_ENDPOINT "https://your-resource.openai.azure.com/"
azd env set AZURE_OPENAI_DEPLOYMENT_NAME "gpt-4.1-mini"
azd up

# Step 3: Grant Azure OpenAI access (use PowerShell, not Git Bash!)
# Get the managed identity principal ID
$MI_ID = az webapp identity show --name app-<unique-id> --resource-group rg-mafstreaming --query principalId -o tsv
# Grant role
az role assignment create --assignee-object-id $MI_ID --assignee-principal-type ServicePrincipal --role "Cognitive Services OpenAI User" --scope "<azure-openai-resource-id>"

# Step 4: Generate Teams manifest
bash scripts/03-teams-manifest.sh

# Step 5: Upload teams-manifest/Mafstreaming.zip to Teams
```

Verify deployment:
```bash
curl https://app-<unique-id>.azurewebsites.net/health
```

### Cleanup

To remove all resources:
```bash
bash scripts/cleanup.sh --env mafstreaming
```

---

## Local Development

### Run Locally

```bash
cd src/TeamsStreamingBot
dotnet restore
dotnet run
```

The bot will start on `http://localhost:5000`.

### Local Testing with Dev Tunnel

1. Install [ngrok](https://ngrok.com/) or use VS Code Dev Tunnels
2. Create a tunnel to your local port:
   ```bash
   ngrok http 5000
   ```
3. Update the Azure Bot messaging endpoint to your tunnel URL + `/api/messages`

## Project Structure

```
TeamsStreaming/
├── scripts/                             # Deployment scripts
│   ├── 01-create-app-registration.sh    # Create Entra app (SingleTenant)
│   ├── 02-deploy.sh                     # Deploy with azd
│   ├── 03-teams-manifest.sh             # Generate Teams package
│   ├── cleanup.sh                       # Remove all resources
│   └── README.md                        # Script documentation
├── src/
│   └── TeamsStreamingBot/
│       ├── Services/
│       │   └── StreamingBot.cs          # Bot with streaming + reasoning
│       ├── Program.cs                   # App setup, AIAgent + IChatClient
│       ├── appsettings.json             # MSAL connection configuration
│       └── TeamsStreamingBot.csproj     # Project file
├── infra/
│   ├── main.bicep                       # Main template with App Insights
│   ├── main.parameters.json             # Parameter values
│   ├── abbreviations.json               # Resource naming conventions
│   └── modules/
│       ├── appserviceplan.bicep         # App Service Plan
│       ├── appservice.bicep             # Web App + Managed Identity
│       ├── botservice.bicep             # Azure Bot (SingleTenant)
│       ├── loganalytics.bicep           # Log Analytics workspace
│       └── applicationinsights.bicep    # Application Insights
├── appManifest/
│   ├── manifest.json                    # Teams app manifest (template)
│   ├── manifest.json.template           # Template with placeholders
│   ├── color.png                        # App icon (192x192)
│   └── outline.png                      # App icon outline (32x32)
├── teams-manifest/                      # Generated manifest packages
├── azure.yaml                           # Azure Developer CLI config
├── .env.sample                          # Environment variables template
└── README.md                            # This file
```

## How Streaming Works

This bot implements true **token-by-token streaming** using the M365 Agents SDK's `StreamingResponse` API combined with `Microsoft.Extensions.AI` streaming:

1. **Informative Update**: Shows status messages ("Thinking...", "Generating response...")
2. **Streaming API**: Uses `IChatClient.GetStreamingResponseAsync()` to receive tokens as they're generated
3. **Real-Time Chunks**: Each token is immediately queued to Teams via `QueueTextChunk()`
4. **Reasoning Output**: System prompt instructs the model to show reasoning before answering

```csharp
// Start with informative update
await turnContext.StreamingResponse.QueueInformativeUpdateAsync("Thinking...", cancellationToken);

// Build messages with reasoning prompt
var messages = new List<ChatMessage>
{
    new ChatMessage(ChatRole.System, SystemPrompt),
    new ChatMessage(ChatRole.User, userMessage)
};

// Stream tokens in real-time
await foreach (var update in _chatClient.GetStreamingResponseAsync(messages, cancellationToken: cancellationToken))
{
    if (!string.IsNullOrEmpty(update.Text))
    {
        // Queue each token immediately to Teams
        turnContext.StreamingResponse.QueueTextChunk(update.Text);
    }
}

// Finalize the response
await turnContext.StreamingResponse.EndStreamAsync(cancellationToken);
```

### Response Format with Reasoning

The bot's system prompt instructs the model to show its thought process:

```
**Reasoning:** [Model's thought process here]

**Answer:** [The actual response here]
```

This provides transparency into how the AI arrives at its answers.

## Configuration Options

| Environment Variable | Description | Required |
|---------------------|-------------|----------|
| `BOT_ID` | Microsoft Entra App Registration ID | Yes |
| `BOT_PASSWORD` | App Registration client secret | Yes |
| `AZURE_OPENAI_ENDPOINT` | Azure OpenAI endpoint URL | Yes |
| `AZURE_OPENAI_DEPLOYMENT_NAME` | Model deployment name | Yes (default: gpt-4o) |

### Managed Identity for Azure OpenAI

This bot uses **Managed Identity** (DefaultAzureCredential) to authenticate with Azure OpenAI - no API keys required! The App Service's system-assigned managed identity must have the **Cognitive Services OpenAI User** role on your Azure OpenAI resource.

## Critical Deployment Details

This section documents important configuration requirements discovered during deployment.

### 1. Single Tenant App Registration

The bot **must** use a **SingleTenant** app registration (not MultiTenant):

```bash
# When creating the app registration, use SingleTenant
az ad app create --display-name "mybot-StreamingBot" --sign-in-audience AzureADMyOrg

# If you already created a MultiTenant app, change it:
az ad app update --id <BOT_ID> --sign-in-audience AzureADMyOrg
```

### 2. Service Principal (Enterprise Application)

After creating the app registration, you **must** create a service principal:

```bash
az ad sp create --id <BOT_ID>
```

> **Why?** The M365 Agents SDK uses MSAL to authenticate with Bot Framework. Without a service principal, MSAL returns error `AADSTS7000229: The client application is missing service principal in the tenant`.

### 3. MSAL Connection Configuration

The M365 Agents SDK requires specific environment variables for MSAL authentication. These are configured in the App Service:

| Environment Variable | Value |
|---------------------|-------|
| `Connections__BotServiceConnection__Assembly` | `Microsoft.Agents.Authentication.Msal` |
| `Connections__BotServiceConnection__Type` | `MsalAuth` |
| `Connections__BotServiceConnection__Settings__ClientId` | `<BOT_ID>` |
| `Connections__BotServiceConnection__Settings__ClientSecret` | `<BOT_PASSWORD>` |
| `Connections__BotServiceConnection__Settings__TenantId` | `<your-tenant-id>` |
| `Connections__BotServiceConnection__Settings__Authority` | `https://login.microsoftonline.com/<tenant-id>` |
| `TokenValidation__Audiences__0` | `<BOT_ID>` |

These are automatically set by the Bicep templates during `azd up`.

### 4. Azure OpenAI RBAC Access

Grant the App Service managed identity access to Azure OpenAI:

```powershell
# Use PowerShell (not Git Bash - see note below)
az role assignment create `
  --assignee-object-id <managed-identity-principal-id> `
  --assignee-principal-type ServicePrincipal `
  --role "Cognitive Services OpenAI User" `
  --scope /subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.CognitiveServices/accounts/<aoai-resource>
```

To find the managed identity principal ID:
```bash
az webapp identity show --name <app-service-name> --resource-group <rg> --query principalId -o tsv
```

> **Git Bash Warning:** Git Bash on Windows converts paths starting with `/subscriptions/...` to Windows paths. Use **PowerShell** or **CMD** for `az role assignment` commands with `--scope`.

### 5. Bot Service Configuration

The Azure Bot Service is configured as:
- **Type**: `SingleTenant` (msaAppType)
- **Messaging Endpoint**: `https://<app-service>.azurewebsites.net/api/messages`
- **Tenant ID**: Your Microsoft Entra tenant ID

## Troubleshooting

### Error: AADSTS7000229 - Missing Service Principal

**Symptom:** Bot receives messages but doesn't respond. Application Insights shows:
```
AADSTS7000229: The client application <BOT_ID> is missing service principal in the tenant
```

**Solution:** Create the service principal:
```bash
az ad sp create --id <BOT_ID>
```

### Error: MSAL Authority Format Error

**Symptom:** Application Insights shows:
```
The authority must be in well-formed URI format
```

**Solution:** Ensure these environment variables are set in App Service:
- `Connections__BotServiceConnection__Settings__TenantId` = your tenant ID
- `Connections__BotServiceConnection__Settings__Authority` = `https://login.microsoftonline.com/<tenant-id>`

### Error: PermissionDenied on Azure OpenAI

**Symptom:** Bot responds with:
```
HTTP 401 PermissionDenied - The principal <id> lacks the required data action Microsoft.CognitiveServices/accounts/OpenAI/deployments/chat/completions/action
```

**Solution:** Grant the managed identity the `Cognitive Services OpenAI User` role on your Azure OpenAI resource (see section 4 above).

### Error: 404 on /api/messages

**Symptom:** Bot Channel Registration test shows 404.

**Solution:** The bot explicitly maps the `/api/messages` endpoint in `Program.cs`. Verify the app is deployed correctly:
```bash
curl https://<app-service>.azurewebsites.net/health
```

### Bot not responding in Teams

1. **Check messaging endpoint** - Must be `https://<app>.azurewebsites.net/api/messages`
2. **Verify Teams channel** - Enabled in Azure Bot Service → Channels
3. **Check App Service logs** - Azure Portal → App Service → Log stream
4. **Verify app is running** - `curl https://<app>.azurewebsites.net/health`
5. **Check Application Insights** - Query for recent exceptions:
   ```kusto
   AppTraces | where TimeGenerated > ago(5m) | order by TimeGenerated desc
   ```

### Streaming not working

1. **Personal scope only** - Streaming only works in 1:1 chats, not group chats or channels
2. **Check model deployment** - Verify the Azure OpenAI deployment exists
3. **Monitor token flow** - Check Application Insights for streaming activity

### Authentication errors (invalid_client)

1. **Verify app type** - Must be SingleTenant (`AzureADMyOrg`)
2. **Check service principal exists** - `az ad sp show --id <BOT_ID>`
3. **Regenerate client secret** if needed:
   ```bash
   az ad app credential reset --id <BOT_ID> --append --years 2
   ```
   Then update `BOT_PASSWORD` in azd env and redeploy.

### Git Bash Path Translation Issue

**Symptom:** Azure CLI commands with `--scope /subscriptions/...` fail with `MissingSubscription` error.

**Cause:** Git Bash converts paths starting with `/` to Windows paths.

**Solution:** Use PowerShell or CMD instead:
```powershell
powershell -Command "az role assignment create --scope '/subscriptions/...'"
```

## Quick Reference

### Redeploy After Code Changes
```bash
azd deploy
```

### View Logs
```bash
az webapp log tail --name <app-name> --resource-group <rg>
```

### Restart App
```bash
az webapp restart --name <app-name> --resource-group <rg>
```

### Check Application Insights
```kusto
// Recent traces and errors
AppTraces | where TimeGenerated > ago(10m) | order by TimeGenerated desc
AppExceptions | where TimeGenerated > ago(10m) | order by TimeGenerated desc
```

### Regenerate Bot Password
```bash
az ad app credential reset --id <BOT_ID> --append --years 2
# Then update in azd env and App Service
azd env set BOT_PASSWORD "<new-password>"
az webapp config appsettings set --name <app> --resource-group <rg> \
  --settings BOT_PASSWORD="<new-password>" \
  Connections__BotServiceConnection__Settings__ClientSecret="<new-password>"
```

## Resources

- [Microsoft Agent Framework](https://github.com/microsoft/agent-framework)
- [M365 Agents SDK](https://learn.microsoft.com/microsoftteams/platform/bots/how-to/teams-conversational-ai/teams-conversation-ai-overview)
- [Teams Streaming UX](https://learn.microsoft.com/microsoftteams/platform/bots/streaming-ux)
- [Azure Developer CLI](https://learn.microsoft.com/azure/developer/azure-developer-cli/)
- [Azure Bot Service](https://azure.microsoft.com/services/bot-services/)

## License

MIT
