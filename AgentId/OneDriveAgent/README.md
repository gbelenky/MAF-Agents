# OneDrive Agent with OBO Authentication

A **.NET 9** bot using **Microsoft Agent Framework (MAF)** with **Azure OpenAI** that helps users manage OneDrive files through Microsoft Teams. Uses the **On-Behalf-Of (OBO) flow** with a single app registration and Federated Identity Credential for secure, secretless user delegation.

**Architecture:**
- **.NET** (`OneDriveAgent/`): Bot + Agent runtime using MAF's `AIAgent` class with `AzureOpenAIClient`
- **Azure AI Services**: Hosts model deployments (gpt-4o-mini)
- **OBO with App Registration**: Single app registration + FIC pattern for secure delegated access

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Roles and Responsibilities](#roles-and-responsibilities)
3. [Deployment Guide](#deployment-guide)
4. [Project Structure](#project-structure)
5. [Local Development](#local-development)
   - [Configure appsettings.Development.json](#configure-appsettingsdevelopmentjson)
   - [Local Testing with Dev Tunnels](#local-testing-with-dev-tunnels)
6. [Token Flow Explained](#token-flow-explained)
7. [Troubleshooting](#troubleshooting)

---

## Architecture Overview

### Identity Architecture

This solution uses a **single-app approach** with Federated Identity Credential (FIC) for secure, secretless authentication in Azure:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      OBO IDENTITY ARCHITECTURE                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌──────────────────────────┐         ┌───────────────────────────────┐    │
│  │   AGENT IDENTITY APP     │         │      MANAGED IDENTITY         │    │
│  │─────────────────────────│         │─────────────────────────────│    │
│  │ • App Registration       │  FIC    │ • Azure Resource              │    │
│  │ • access_as_user scope   │<────────│ • No client secret needed     │    │
│  │ • Graph delegated perms  │         │ • Works in Azure only         │    │
│  │ • Pre-authorized clients │         │ • Linked to app via FIC       │    │
│  └──────────────────────────┘         └───────────────────────────────┘    │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Why This Approach?

| Component | Purpose | Benefit |
|-----------|---------|---------|
| **Agent Identity App** | Single app registration with exposed API and Graph permissions | Simplified setup, single entity to manage |
| **Managed Identity** | Provides secure authentication without secrets | No secret rotation, no credential leakage |
| **Federated Identity Credential** | Links MI to App Registration | Enables secretless OBO in Azure |

### Teams Integration Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         MICROSOFT TEAMS                                     │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    OneDrive Agent Bot                                │   │
│  │  User → Teams SSO → Bot Token Service → Graph Token → Graph API     │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                      AZURE APP SERVICE                                      │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    OneDrive Agent API                                │   │
│  │  Bot Framework → MAF Agent → Azure OpenAI → Function Tools          │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                    MICROSOFT GRAPH API                                      │
│  OneDrive files accessed with user's delegated permissions                  │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Roles and Responsibilities

### Task Matrix

| Task | Who | Script | Notes |
|------|-----|--------|-------|
| Create Agent Identity App | Admin | `01-admin-create-apps.sh` | Creates app + permissions |
| Add Graph permissions + admin consent | Admin | `01-admin-create-apps.sh` | Automated |
| Deploy infrastructure | Developer | `azd up` | Bicep automation |
| Create Federated Identity Credential | Admin | `03-admin-create-fic.sh` | After `azd up` |
| Configure Bot OAuth | Admin | `04-admin-bot-oauth.sh` | For Teams SSO |
| Generate Teams manifest | Developer | `05-dev-teams-manifest.sh` | After OAuth setup |

*Admin = Entra ID admin (or developer with Application.ReadWrite.All permission)*

---

## Deployment Guide

### Prerequisites

| Requirement | Developer | Entra Admin |
|-------------|-----------|-------------|
| Azure CLI installed | ✓ Required | ✓ Required |
| Azure subscription (Contributor) | ✓ Required | |
| .NET 9 SDK | ✓ Required | |
| Azure Developer CLI (`azd`) | ✓ Required | |
| Entra ID Global Admin or App Admin | | ✓ Required |

### Deployment Flow

```
┌── ENTRA ADMIN ─────────────────────────────────────────────────────────────┐
│  STEP 1: bash scripts/01-admin-create-apps.sh                              │
│          ↳ Creates Agent Identity app + Graph permissions                  │
│          ↳ Output: handoff/01-admin-output-{env}.txt                       │
│          ↳ Send file to Developer                                          │
└────────────────────────────────────────────────────────────────────────────┘
                              ↓
┌── DEVELOPER ───────────────────────────────────────────────────────────────┐
│  azd env new {env-name}                                                    │
│  azd env set AGENT_IDENTITY_CLIENT_ID "<from-admin>"                       │
│                                                                   │
│  STEP 2: azd up                                                            │
│          ↳ Deploys Azure resources                                         │
│                                                                            │
│  bash scripts/02-dev-generate-handoff.sh                                   │
│          ↳ Output: handoff/02-dev-handoff-{env}.txt                        │
│          ↳ Send file to Admin                                              │
└────────────────────────────────────────────────────────────────────────────┘
                              ↓
┌── ENTRA ADMIN ─────────────────────────────────────────────────────────────┐
│  STEP 3: bash scripts/03-admin-create-fic.sh                               │
│          ↳ Links Managed Identity to Agent Identity app                    │
│                                                                            │
│  STEP 4: bash scripts/04-admin-bot-oauth.sh                                │
│          ↳ Creates Bot OAuth connection for Teams SSO                      │
└────────────────────────────────────────────────────────────────────────────┘
                              ↓
┌── DEVELOPER ───────────────────────────────────────────────────────────────┐
│  STEP 5: bash scripts/05-dev-teams-manifest.sh                             │
│          ↳ Output: teams-manifest/OneDriveAgent.zip                        │
│                                                                            │
│  STEP 6: Upload OneDriveAgent.zip to Teams Admin Center                    │
└────────────────────────────────────────────────────────────────────────────┘
```

### Handoff Values

| Value | Set By | Used By | Purpose |
|-------|--------|---------|---------|
| `TENANT_ID` | Both | Both | Azure AD tenant |
| `AGENT_IDENTITY_CLIENT_ID` | Admin | Developer | App registration ID |
| `MANAGED_IDENTITY_CLIENT_ID` | Developer | Admin | For FIC creation |
| `APP_SERVICE_URL` | Developer | Both | Deployed app URL |

---

## Project Structure

```
OneDriveAgent/
├── Program.cs                      # App startup + DI configuration
├── appsettings.json               # Production settings
├── appsettings.Development.json   # Local dev settings
├── Models/
│   └── DriveModels.cs             # OneDrive data models
└── Services/
    ├── AgentOboConfig.cs          # Configuration POCO
    ├── AgentOboTokenService.cs    # OBO token exchange logic
    ├── BotConfig.cs               # Bot and Teams settings
    ├── MafAgentService.cs         # MAF AIAgent setup
    ├── OneDriveAgentBot.cs        # Bot Framework handler
    └── OneDriveService.cs         # OneDrive Graph API wrapper
```

### Key Files

| File | Purpose |
|------|---------|
| [AgentOboTokenService.cs](Services/AgentOboTokenService.cs) | OBO token exchange using MSAL |
| [OneDriveAgentBot.cs](Services/OneDriveAgentBot.cs) | Bot message handler + SSO flow |
| [MafAgentService.cs](Services/MafAgentService.cs) | MAF AIAgent with function tools |
| [OneDriveService.cs](Services/OneDriveService.cs) | Graph API calls for OneDrive |

---

## Local Development

### Configure appsettings.Development.json

For local development, you need a client secret (secrets aren't needed in Azure due to FIC):

```json
{
  "AgentObo": {
    "TenantId": "<your-tenant-id>",
    "ClientId": "<agent-identity-client-id>",
    "ClientSecret": "<client-secret-for-local-dev>"
  },
  "AzureOpenAI": {
    "Endpoint": "https://ai-<env>.cognitiveservices.azure.com/",
    "DeploymentName": "gpt-4o-mini"
  }
}
```

> **Note:** Get a client secret from Entra ID > App registrations > Agent Identity > Certificates & secrets. This is only needed for local development.

### Build and Run

```bash
cd OneDriveAgent
dotnet build
dotnet run
```

Default endpoint: `https://localhost:5001`

### Test the Health Endpoint

```bash
curl https://localhost:5001/health
# Should return "Healthy"
```

### Local Testing with Dev Tunnels

To test the bot locally with Teams, you need to expose your local server to the internet using dev tunnels.

#### Prerequisites

1. Install the dev tunnels CLI:
   ```bash
   # Windows (winget)
   winget install Microsoft.devtunnel

   # macOS (Homebrew)
   brew install --cask devtunnel

   # Or install the VS Code extension: "Dev Tunnels"
   ```

2. Login to dev tunnels:
   ```bash
   devtunnel user login
   ```

#### Create a Persistent Dev Tunnel

Create a named tunnel for your bot (only needed once):

```bash
# Create a persistent tunnel with anonymous access
devtunnel create --name onedrive-bot --allow-anonymous

# Add a port mapping for your local bot (port 5001)
devtunnel port create onedrive-bot --port-number 5001 --protocol https
```

#### Start the Tunnel

```bash
# Start the tunnel (run this in a separate terminal)
devtunnel host onedrive-bot

# Output will show the tunnel URL, e.g.:
# Connect via browser: https://abc123.devtunnels.ms
```

#### Update the Bot Messaging Endpoint

Update the Azure Bot's messaging endpoint to point to your dev tunnel:

```bash
# Get your environment name
ENV_NAME=$(azd env get-value AZURE_ENV_NAME)
TUNNEL_URL="https://<your-tunnel-id>.devtunnels.ms"  # From devtunnel host output

# Update the Bot messaging endpoint
az bot update \
    --name "bot-${ENV_NAME}" \
    --resource-group "rg-${ENV_NAME}" \
    --endpoint "${TUNNEL_URL}/api/messages"
```

Or manually in the Azure Portal:
1. Go to **Azure Bot** resource → **Configuration**
2. Change **Messaging endpoint** to: `https://<your-tunnel-id>.devtunnels.ms/api/messages`
3. Click **Apply**

#### Run and Debug Locally

1. Start the dev tunnel in one terminal:
   ```bash
   devtunnel host onedrive-bot
   ```

2. Run the bot in another terminal (or VS Code debugger):
   ```bash
   cd OneDriveAgent
   dotnet run
   ```

3. Open Teams and chat with your bot - requests will route to your local machine

#### Restore Production Endpoint

After debugging, restore the Azure endpoint:

```bash
ENV_NAME=$(azd env get-value AZURE_ENV_NAME)
APP_URL=$(az webapp show --name "app-${ENV_NAME}" --resource-group "rg-${ENV_NAME}" --query "defaultHostName" -o tsv)

az bot update \
    --name "bot-${ENV_NAME}" \
    --resource-group "rg-${ENV_NAME}" \
    --endpoint "https://${APP_URL}/api/messages"
```

#### Dev Tunnel Tips

- **Persistent tunnels**: Use `devtunnel create --name <name>` for consistent URLs across sessions
- **VS Code integration**: Use the Dev Tunnels extension to manage tunnels from the IDE
- **Anonymous access**: `--allow-anonymous` lets the Bot Framework reach your tunnel without auth
- **Multiple ports**: You can add more ports if needed (e.g., for a frontend)

---

## Token Flow Explained

### Azure Deployment (Secretless)

In Azure, the OBO flow uses Managed Identity + FIC for secretless authentication:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                        AZURE OBO FLOW (SECRETLESS)                           │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  Step 1: User authenticates via Teams SSO                                   │
│  ─────────────────────────────────────────                                   │
│  User → Teams → Bot receives user token                                      │
│                    Audience: Agent Identity App                              │
│                                                                              │
│  Step 2: Bot gets MI token                                                   │
│  ─────────────────────────────                                               │
│  Managed Identity → IMDS (169.254.169.254) → MI Token                        │
│                                               Audience: api://AzureADToken.. │
│                                                                              │
│  Step 3: OBO Exchange                                                        │
│  ────────────────────                                                        │
│  POST /oauth2/v2.0/token                                                     │
│    client_id = Agent Identity                                                │
│    client_assertion = MI Token (via FIC)                                     │
│    assertion = User Token (from Teams)                                       │
│    scope = https://graph.microsoft.com/.default                              │
│    grant_type = urn:ietf:params:oauth:grant-type:jwt-bearer                  │
│                    │                                                         │
│                    v                                                         │
│              Graph Token (user's permissions)                                │
│                                                                              │
│  Step 4: Call Graph API                                                      │
│  ──────────────────────                                                      │
│  GET https://graph.microsoft.com/v1.0/me/drive/root/children                 │
│  Authorization: Bearer {Graph Token}                                        │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Local Development (With Secret)

For local development (no MI available), use a client secret:

```
User Token → OBO with Client Secret → Graph Token
```

The secret is configured in `appsettings.Development.json` and only used locally.

---

## Troubleshooting

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| "Token exchange failed" | FIC not created | Run `03-admin-create-fic.sh` |
| "AADSTS65001: Consent required" | Admin consent not granted | Re-run `01-admin-create-apps.sh` |
| "Invalid audience" | Wrong scope in token request | Check `access_as_user` scope on app |
| Health endpoint returns error | App not deployed correctly | Run `azd deploy api` |

### Verify FIC Configuration

```bash
# List FICs on the Agent Identity app
az rest --method GET \
  --uri "https://graph.microsoft.com/v1.0/applications(appId='<agent-identity-id>')/federatedIdentityCredentials"
```

### Check Bot OAuth Connection

```bash
az bot authsetting list \
  --name bot-<env> \
  --resource-group rg-<env>
```

---

## References

- [Microsoft Agent Framework](https://github.com/microsoft/agents)
- [OBO Flow Documentation](https://learn.microsoft.com/azure/active-directory/develop/v2-oauth2-on-behalf-of-flow)
- [Federated Identity Credentials](https://learn.microsoft.com/azure/active-directory/develop/workload-identity-federation)
- [Bot Framework SSO](https://learn.microsoft.com/microsoftteams/platform/bots/how-to/authentication/bot-sso-overview)
