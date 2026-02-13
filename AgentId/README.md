# OneDrive Agent with Microsoft Entra Agent ID

An AI-powered OneDrive assistant that runs in **Microsoft Teams** using the **Microsoft Entra Agent ID On-Behalf-Of (OBO) flow** for secure user delegation.

## Quick Start

### For Developers

```bash
# 1. Clone and prepare
git clone <repo> && cd AgentId
uv sync          # Python dependencies (for agent management)
dotnet build     # .NET build

# 2. Get app IDs from your Entra Admin
azd env set BLUEPRINT_CLIENT_ID "<from-admin>"
azd env set AGENT_IDENTITY_CLIENT_ID "<from-admin>"
azd env set ENABLE_BOT "true"
azd env set BOT_MICROSOFT_APP_ID "<same-as-agent-identity-id>"

# 3. Deploy to Azure
azd up

# 4. Verify deployment succeeded
curl https://app-<env-name>.azurewebsites.net/health
# Should return "Healthy". If not, redeploy: azd deploy api

# 5. Provide MI Client ID to Admin (shown at end of azd up)
azd env get-value MANAGED_IDENTITY_CLIENT_ID

# 5. After Admin completes FIC + OAuth setup, generate Teams app
bash scripts/05-dev-teams-manifest.sh

# 6. Install Teams app
# Upload teams-manifest/OneDriveAgent.zip to Teams
```

### For Entra ID Admins

Run the automated setup script:

```bash
bash scripts/01-admin-create-apps.sh
```

This creates:
- Blueprint app registration
- Agent Identity app with `access_as_user` scope  
- Graph API permissions (`Files.Read`, `Files.ReadWrite`, `User.Read`)
- Pre-authorized Teams clients for SSO

**After developer runs `azd up`, complete FIC setup:**

```bash
bash scripts/03-admin-create-fic.sh
```

**Create bot OAuth connection:**

```bash
bash scripts/04-admin-bot-oauth.sh \
  --bot-app-id <agent-identity-id> \
  --resource-group rg-<env-name> \
  --bot-name bot-<env-name>
```

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         MICROSOFT TEAMS                                 │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                    OneDrive Agent Bot                            │   │
│  │  User → Teams SSO → Bot Token Service → Graph Token → Graph API │   │
│  └─────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                      AZURE APP SERVICE                                  │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                    OneDrive Agent API                            │   │
│  │  Bot Framework → MAF Agent → Azure OpenAI → Function Tools       │   │
│  └─────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    MICROSOFT GRAPH API                                  │
│  OneDrive files accessed with user's delegated permissions              │
└─────────────────────────────────────────────────────────────────────────┘
```

## Identity Approach: Working-Version vs Foundry Agent ID

This solution uses a **single-app approach** (Working-Version) rather than Microsoft's **two-tier Foundry Agent ID** approach. Both are functionally equivalent for OBO scenarios.

### Foundry Agent ID (2-tier):
```
Blueprint (App Registration)
├── Permissions (Graph delegated)
├── FIC (links to MI)
└── Agent Identity (child app)
    └── Runtime identity for token exchange
```

### Working-Version (1-tier):
```
Agent Identity App (App Registration)
├── Permissions (Graph delegated)
├── FIC (links to MI)
└── Used directly for token exchange
```

### What's the same:
- Both use an App Registration as the `client_id` for OBO
- Both have FIC linking App Service MI → App Registration
- Both define delegated permissions on the app
- Both exchange user token for Graph token via OBO

### What's different:
- Foundry has 2 apps (Blueprint parent → Agent Identity child)
- Working-version has 1 app (serves both purposes)
- Foundry marks apps with special "Agent" type metadata
- Working-version is a regular app registration

> **Why Working-Version?** The Foundry Agent ID approach currently blocks API modifications to Blueprints, requiring manual Portal steps. The Working-Version approach is fully scriptable and provides identical OBO functionality.

## Project Structure

```
AgentId/
├── OneDriveAgent/          # .NET 9 bot + agent application
│   ├── Services/           # Bot handler, MAF agent, OBO token service
│   ├── Program.cs          # App configuration and DI
│   └── README.md           # Detailed documentation
├── src/                    # Python agent management
│   └── agent_manager.py    # Create/delete Standard Agents
├── infra/                  # Azure Bicep infrastructure
├── scripts/                # Admin and setup scripts
│   ├── 00-admin-cleanup.sh      # Clean up app registrations
│   ├── 01-admin-create-apps.sh  # Step 1: Create app registrations
│   ├── 02-dev-generate-handoff.sh # Step 2: Dev generates admin handoff
│   ├── 03-admin-create-fic.sh   # Step 3: Create FIC
│   ├── 04-admin-bot-oauth.sh    # Step 4: Configure bot OAuth
│   ├── 05-dev-teams-manifest.sh # Step 5: Generate Teams manifest
│   └── cleanup-deploy.sh        # Full cleanup (Azure + Entra + azd)
├── handoff/                # Handoff files (gitignored - contains secrets)
│   ├── 01-admin-output-*.txt    # Admin → Developer
│   └── 02-dev-handoff-*.txt     # Developer → Admin
├── teams-manifest/         # Teams app package
└── azure.yaml              # azd deployment configuration
```

## Documentation

See [OneDriveAgent/README.md](OneDriveAgent/README.md) for:
- **[Local Development & Testing](OneDriveAgent/README.md#local-development--testing)** - Build, run, and debug locally
- Complete deployment guide (5 phases)
- Token flow explanations
- Troubleshooting guide
- API reference

## Deployment Steps Overview

| Step | Command | Role | Purpose | Handoff File |
|------|---------|------|---------|--------------|
| 0 | `azd env new {env}` | Developer | Create azd environment | - |
| 1 | `01-admin-create-apps.sh` | Entra Admin | Create Entra app registrations | `handoff/01-admin-output-{env}.txt` → Dev |
| 2 | `azd up` | Developer | Deploy Azure resources | - |
| - | `02-dev-generate-handoff.sh` | Developer | (Optional) Generate handoff for admin | `handoff/02-dev-handoff-{env}.txt` → Admin |
| 3 | `03-admin-create-fic.sh` | Entra Admin | Create Federated Identity Credential | - |
| 4 | `04-admin-bot-oauth.sh` | Entra Admin | Configure bot OAuth connection | - |
| 5 | `05-dev-teams-manifest.sh` | Developer | Generate Teams app package | `teams-manifest/OneDriveAgent.zip` |
| 6 | Upload to Teams | Developer | Install app in Teams | - |

> **Note:** All handoff files are saved to `handoff/` folder which is gitignored (contains secrets).

**Utility Scripts:**
| Script | Role | Purpose |
|--------|------|---------|
| `00-admin-cleanup.sh` | Entra Admin | Delete app registrations (reset) |
| `cleanup-deploy.sh` | Developer | Full cleanup: Azure resources, Entra apps, azd env |

## Client Secrets

This solution creates **two separate client secrets** for different purposes:

| Secret Name | Created By | Purpose | Required For |
|-------------|-----------|---------|--------------|
| `LocalDev-Secret-{date}` | Step 1 script | Local development and debugging | Running bot locally without Managed Identity |
| `BotOAuth-Secret-{date}` | Step 4 script | Azure Bot Service token exchange | SSO in Teams - Bot Service calls Entra ID to exchange tokens |

**Important notes:**
- Both secrets are for the **same app registration** (Agent Identity)
- The Bot OAuth secret is used by Azure Bot Service, not your code
- For production, consider using certificates instead of secrets
- Secrets expire after the configured period (default: 1-2 years)

## Deployment Workflows

### Option A: Same Person (Dev + Admin)

When developer has Entra Admin permissions, scripts auto-detect values from azd:

```
┌─────────────────────────────────────────────────────────────────┐
│  STEP 0: azd env new {env-name}                                 │
│  STEP 1: bash scripts/01-admin-create-apps.sh                   │
│          ↳ Creates Entra apps, saves IDs to azd env             │
│  STEP 2: azd up                                                 │
│          ↳ Deploys Azure resources, creates Managed Identity    │
│  STEP 3: bash scripts/03-admin-create-fic.sh                    │
│          ↳ Links Managed Identity to Agent Identity             │
│  STEP 4: bash scripts/04-admin-bot-oauth.sh                     │
│          ↳ Creates Bot OAuth connection with secret             │
│  STEP 5: bash scripts/05-dev-teams-manifest.sh                  │
│          ↳ Generates Teams app package                          │
│  STEP 6: Upload OneDriveAgent.zip to Teams Admin Center         │
└─────────────────────────────────────────────────────────────────┘
```

**Commands:**
```bash
azd env new myagent
bash scripts/01-admin-create-apps.sh
azd up
bash scripts/03-admin-create-fic.sh
bash scripts/04-admin-bot-oauth.sh
bash scripts/05-dev-teams-manifest.sh
```

### Option B: Separate Developer and Entra Admin

When developer and admin are different people:

```
┌── ENTRA ADMIN ────────────────────────────────────────────────────┐
│  STEP 1: bash scripts/01-admin-create-apps.sh                     │
│          ↳ Output: handoff/01-admin-output-{env}.txt              │
│          ↳ Send file to Developer                                 │
└───────────────────────────────────────────────────────────────────┘
                              ↓
┌── DEVELOPER ──────────────────────────────────────────────────────┐
│  azd env new {env-name}                                           │
│  azd env set BLUEPRINT_CLIENT_ID "<from-admin>"                   │
│  azd env set AGENT_IDENTITY_CLIENT_ID "<from-admin>"              │
│  azd env set BOT_MICROSOFT_APP_ID "<from-admin>"                  │
│  azd env set ENABLE_BOT "true"                                    │
│                                                                   │
│  STEP 2: azd up                                                   │
│          ↳ Deploys Azure resources                                │
│                                                                   │
│  bash scripts/02-dev-generate-handoff.sh                          │
│          ↳ Output: handoff/02-dev-handoff-{env}.txt               │
│          ↳ Send file to Admin                                     │
└───────────────────────────────────────────────────────────────────┘
                              ↓
┌── ENTRA ADMIN ────────────────────────────────────────────────────┐
│  (Place 02-dev-handoff-{env}.txt in handoff/ folder)              │
│                                                                   │
│  STEP 3: bash scripts/03-admin-create-fic.sh                      │
│          ↳ Auto-detects values from handoff file                  │
│                                                                   │
│  STEP 4: bash scripts/04-admin-bot-oauth.sh                       │
│          ↳ Creates Bot OAuth secret and connection                │
│          ↳ Notify Developer when done                             │
└───────────────────────────────────────────────────────────────────┘
                              ↓
┌── DEVELOPER ──────────────────────────────────────────────────────┐
│  STEP 5: bash scripts/05-dev-teams-manifest.sh                    │
│          ↳ Output: teams-manifest/OneDriveAgent.zip               │
│                                                                   │
│  STEP 6: Upload OneDriveAgent.zip to Teams Admin Center           │
└───────────────────────────────────────────────────────────────────┘
```

## Azure Resources

After `azd up`, your resource group contains:

| Resource | Purpose |
|----------|---------|
| `app-{env}` | App Service hosting the bot |
| `ai-{env}` | Azure OpenAI with gpt-4o-mini |
| `bot-{env}` | Azure Bot Service |
| `id-{env}` | User-Assigned Managed Identity |
| `appi-{env}` | Application Insights |

## Requirements

- Azure subscription with Contributor access
- Entra ID admin privileges (for app registrations)
- [Azure Developer CLI (azd)](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd)
- [.NET 9 SDK](https://dotnet.microsoft.com/download)
- [uv](https://github.com/astral-sh/uv) for Python dependencies

## License

See [LICENSE](LICENSE) for details.
