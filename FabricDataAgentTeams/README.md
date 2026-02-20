# Fabric Data Agent Teams Bot

A Microsoft Teams bot that connects users to **Microsoft Fabric Data Agents** using **SSO authentication**. Users can ask natural language questions about their data directly in Teams.

## Deployment

This deployment requires coordination between **Developer** and **Entra Admin** roles using handoff files.

```
┌── DEVELOPER ──────────────────────────────────────────────────────┐
│  STEP 0: Choose environment name (e.g., fabricagent)              │
│          ↳ Tell Admin the name                                    │
└───────────────────────────────────────────────────────────────────┘
                              ↓
┌── ENTRA ADMIN ────────────────────────────────────────────────────┐
│  STEP 1: bash scripts/01-admin-create-apps.sh --prefix {name}     │
│          ↳ Output: handoff/01-admin-output-{name}.txt             │
│          ↳ Send file to Developer (securely)                      │
└───────────────────────────────────────────────────────────────────┘
                              ↓
┌── DEVELOPER ──────────────────────────────────────────────────────┐
│  STEP 2: azd env new {name}                                       │
│          azd env set BOT_CLIENT_ID "<from-admin-file>"           │
│          azd env set FABRIC_WORKSPACE_ID "<workspace-id>"         │
│          azd env set FABRIC_AGENT_ITEM_ID "<agent-item-id>"       │
│          azd up                                                   │
│          bash scripts/02-dev-generate-handoff.sh                  │
│          ↳ Output: handoff/02-dev-handoff-{name}.txt              │
│          ↳ Send file to Admin (securely)                          │
└───────────────────────────────────────────────────────────────────┘
                              ↓
┌── ENTRA ADMIN ────────────────────────────────────────────────────┐
│  STEP 3: bash scripts/03-admin-bot-oauth.sh \                     │
│            --handoff-file 02-dev-handoff-{name}.txt               │
│          ↳ Creates OAuth connection + sets App Service secret     │
│          ↳ Notify Developer when done                             │
└───────────────────────────────────────────────────────────────────┘
                              ↓
┌── DEVELOPER ──────────────────────────────────────────────────────┐
│  STEP 4: bash scripts/04-dev-teams-manifest.sh                    │
│  STEP 5: Upload teams-manifest/{AgentName}.zip to Teams           │
└───────────────────────────────────────────────────────────────────┘
```

> **Note:** This solution uses SingleTenant auth with client secrets instead of Managed Identity with FIC.

### Step 0: Developer Chooses Name

Developer decides on environment name (e.g., `fabricagent`) and tells Entra Admin.

### Step 1: Entra Admin Creates App Registration

```bash
bash scripts/01-admin-create-apps.sh --prefix fabricagent
```

Creates app registration with Fabric API permissions and Teams SSO pre-authorization.

**Send `handoff/01-admin-output-fabricagent.txt` to Developer**

### Step 2: Developer Deploys to Azure

```bash
# Create environment and set app ID from admin handoff file
azd env new fabricagent
azd env set BOT_CLIENT_ID "<APP_ID from admin handoff file>"

# Set Fabric Data Agent details
azd env set FABRIC_WORKSPACE_ID "<your-fabric-workspace-id>"
azd env set FABRIC_AGENT_ITEM_ID "<your-fabric-agent-id>"

# Deploy to Azure
azd up

# Verify deployment
curl https://app-fabricagent.azurewebsites.net/health

# Generate handoff file for Admin
bash scripts/02-dev-generate-handoff.sh
```

**Send `handoff/02-dev-handoff-fabricagent.txt` to Admin**

### Step 3: Entra Admin Configures Bot OAuth

```bash
bash scripts/03-admin-bot-oauth.sh --handoff-file /path/to/02-dev-handoff-fabricagent.txt
```

This script:
- Configures SSO (Application ID URI, access_as_user scope, pre-authorized Teams clients)
- Adds Fabric API permissions (`DataAgent.Execute.All`, `MLModel.Execute.All`)
- Grants admin consent for Fabric API
- Creates a client secret for Bot Framework authentication
- Configures the OAuth connection for Teams SSO
- Sets `MicrosoftAppPassword` in the App Service

**Notify Developer when complete.**

### Step 4: Developer Generates Teams App

```bash
bash scripts/04-dev-teams-manifest.sh
# Upload teams-manifest/<AgentName>.zip to Teams Admin Center
```

> **Note:** After completing all steps, wait **2-5 minutes** before testing in Teams. The Bot Service, OAuth connection, and Teams manifest need time to propagate.

### Handoff Files

| File | Direction | Contains |
|------|-----------|----------|
| `01-admin-output-{name}.txt` | Admin → Developer | App ID, Tenant ID |
| `02-dev-handoff-{name}.txt` | Developer → Admin | MI ID, Resource Group, Bot Name |

> All handoff files are saved to `handoff/` folder which is gitignored (contains secrets).

## Architecture

```
┌────────────────────────────────────────────────────────────────────────┐
│                         MICROSOFT TEAMS                                │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                  Fabric Data Agent Bot                          │   │
│  │  User → Teams SSO → Bot Token Service → Fabric Token → Fabric   │   │
│  └─────────────────────────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                      AZURE APP SERVICE                                 │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                  Fabric Data Agent API                          │   │
│  │  Bot Framework → aiohttp → Fabric Agent Client → Threads API    │   │
│  └─────────────────────────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                 MICROSOFT FABRIC DATA AGENT API                        │
│  Data queries executed with user's delegated permissions               │
└────────────────────────────────────────────────────────────────────────┘
```

**Stack:**
- **Bot Framework SDK** (`botbuilder-core`) - Teams bot messaging infrastructure
- **aiohttp** - Async HTTP server and client
- **Fabric Data Agent API** - OpenAI Assistants-compatible Threads API

## Project Structure

```
FabricDataAgentTeams/
├── app/                    # Python application
│   ├── __init__.py
│   ├── bot.py              # Teams bot handler with SSO
│   ├── config.py           # Environment configuration
│   └── fabric_agent.py     # Fabric Data Agent client
├── infra/                  # Azure Bicep infrastructure
│   ├── main.bicep
│   ├── main.parameters.json
│   └── app/
│       ├── bot/            # Bot Service
│       ├── identity/       # Managed Identity
│       ├── monitoring/     # Log Analytics + App Insights
│       └── web/            # App Service
├── scripts/                # Admin and setup scripts
│   ├── 01-admin-create-apps.sh  # Step 1: Create app registrations
│   ├── 02-dev-generate-handoff.sh # Step 2: Dev generates admin handoff
│   ├── 03-admin-bot-oauth.sh    # Step 3: Configure bot OAuth
│   └── 04-dev-teams-manifest.sh # Step 4: Generate Teams manifest
├── handoff/                # Handoff files (gitignored - contains secrets)
├── teams-manifest/         # Teams app package
│   ├── manifest.json.template
│   ├── color.png
│   └── outline.png
├── main.py                 # Entry point
├── pyproject.toml          # Python dependencies
└── azure.yaml              # azd deployment configuration
```

## Local Development

1. Copy `.env.example` to `.env` and fill in values:
   ```bash
   cp .env.example .env
   ```

2. Install dependencies:
   ```bash
   pip install -e .
   # OR with uv:
   uv sync
   ```

3. Run the bot:
   ```bash
   python main.py
   # OR with uv:
   uv run python main.py
   ```

4. Use [Bot Framework Emulator](https://github.com/microsoft/BotFramework-Emulator) or [ngrok](https://ngrok.com/) to test locally.

## Authentication Approach

This solution uses **SingleTenant authentication with client secrets** for Bot Framework:

| Component | Auth Method | Why |
|-----------|-------------|-----|
| Bot Framework | Client Secret | Python Bot SDK doesn't fully support FIC/Managed Identity |
| Fabric API Access | OAuth Connection | User tokens exchanged via Bot Service OAuth |
| App Service → Azure | User-Assigned MI | For Azure resource access (Key Vault, etc.) |

This differs from the .NET AgentId project which uses FIC (Federated Identity Credentials) with Managed Identity throughout.

## Client Secrets

This solution creates **two client secrets** in the same app registration:

| Secret Name | Created By | Purpose | Required For |
|-------------|-----------|---------|--------------|
| `LocalDev-Secret-{date}` | Step 1 script | Local development | Running bot locally |
| `BotOAuth-Secret-{date}` | Step 4 script | **Both** Bot Framework auth AND OAuth connection | Production bot authentication + SSO token exchange |

**Important notes:**
- Step 4 sets `MicrosoftAppPassword` in App Service using the same secret
- The Bot OAuth secret is used by **both** your bot code AND Azure Bot Service
- For production, consider using certificates instead of secrets
- Secrets expire after the configured period (default: 2 years)

## Azure Resources

After `azd up`, your resource group contains:

| Resource | Purpose |
|----------|---------|
| `app-{env}` | App Service hosting the Python bot |
| `bot-{env}` | Azure Bot Service for Teams |
| `id-{env}` | User-Assigned Managed Identity |
| `law-{env}` | Log Analytics Workspace |
| `appi-{env}` | Application Insights |

## Configuration

| Variable | Description |
|----------|-------------|
| `BOT_MICROSOFT_APP_ID` | Bot app registration client ID |
| `BOT_MICROSOFT_APP_TENANT_ID` | Azure AD tenant ID |
| `BOT_OAUTH_CONNECTION_NAME` | OAuth connection name (default: `fabric-connection`) |
| `FABRIC_WORKSPACE_ID` | Fabric workspace containing the Data Agent |
| `FABRIC_AGENT_ITEM_ID` | Fabric Data Agent item ID |
| `PORT` | Server port (default: `8080`) |

## Troubleshooting

### SSO Not Working
1. Verify OAuth connection in Azure Portal (Bot Service → Configuration)
2. Check that admin consent was granted
3. Ensure Teams clients are pre-authorized in app registration
4. Wait 2-5 minutes after changes for propagation

### Token Exchange Fails
1. Check FIC is configured correctly (Step 3) - needed for Fabric API access
2. Verify the OAuth connection in Azure Portal has correct scopes
3. Check bot logs in Application Insights

### Bot Not Responding
1. Verify App Service is running: `curl https://app-{env}.azurewebsites.net/health`
2. Check App Service logs in Azure Portal
3. Verify Fabric workspace and agent IDs are correct

## Requirements

- Python 3.10+
- Azure subscription with Contributor access
- Entra ID admin privileges (for app registrations)
- [Azure Developer CLI (azd)](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd)
- A published **Microsoft Fabric Data Agent**

## License

MIT
