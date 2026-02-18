# OneDrive Agent with OBO Authentication

An AI-powered OneDrive assistant that runs in **Microsoft Teams** using the **M365 Agents SDK** and **Microsoft Agents Framework (MAF)** with the **On-Behalf-Of (OBO) flow** for secure user delegation.

## Deployment

This deployment requires coordination between **Developer** and **Entra Admin** roles using handoff files.

```
┌── DEVELOPER ──────────────────────────────────────────────────────┐
│  STEP 0: Choose environment name (e.g., myagent)                  │
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
│          azd env set AGENT_IDENTITY_CLIENT_ID "<from-admin-file>" │
│          azd up                                                   │
│          bash scripts/02-dev-generate-handoff.sh                  │
│          ↳ Output: handoff/02-dev-handoff-{name}.txt              │
│          ↳ Send file to Admin (securely)                          │
└───────────────────────────────────────────────────────────────────┘
                              ↓
┌── ENTRA ADMIN ────────────────────────────────────────────────────┐
│  STEP 3: bash scripts/03-admin-create-fic.sh \                    │
│            --handoff-file 02-dev-handoff-{name}.txt               │
│  STEP 4: bash scripts/04-admin-bot-oauth.sh \                     │
│            --handoff-file 02-dev-handoff-{name}.txt               │
│          ↳ Notify Developer when done                             │
└───────────────────────────────────────────────────────────────────┘
                              ↓
┌── DEVELOPER ──────────────────────────────────────────────────────┐
│  STEP 5: bash scripts/05-dev-teams-manifest.sh                    │
│  STEP 6: Upload teams-manifest/{AgentName}.zip to Teams           │
└───────────────────────────────────────────────────────────────────┘
```

### Step 0: Developer Chooses Name

Developer decides on environment name (e.g., `myagent`) and tells Entra Admin.

### Step 1: Entra Admin Creates App Registration

```bash
bash scripts/01-admin-create-apps.sh --prefix myagent
```

Creates app registration with Graph permissions and Teams SSO pre-authorization.

**Send `handoff/01-admin-output-myagent.txt` to Developer**

### Step 2: Developer Deploys to Azure

```bash
# Create environment and set app ID from admin handoff file
azd env new myagent
azd env set AGENT_IDENTITY_CLIENT_ID "<APP_ID from admin handoff file>"

# Deploy to Azure
azd up

# Verify deployment
curl https://app-myagent.azurewebsites.net/health

# Generate handoff file for Admin
bash scripts/02-dev-generate-handoff.sh
```

**Send `handoff/02-dev-handoff-myagent.txt` to Admin**

### Steps 3-4: Entra Admin Creates FIC + OAuth

```bash
bash scripts/03-admin-create-fic.sh --handoff-file /path/to/02-dev-handoff-myagent.txt
bash scripts/04-admin-bot-oauth.sh --handoff-file /path/to/02-dev-handoff-myagent.txt
```

**Notify Developer when complete.**

### Steps 5-6: Developer Generates Teams App

```bash
bash scripts/05-dev-teams-manifest.sh
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
│  │                    OneDrive Agent Bot                           │   │
│  │  User → Teams SSO → Bot Token Service → Graph Token → Graph API │   │
│  └─────────────────────────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                      AZURE APP SERVICE                                 │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                    OneDrive Agent API                           │   │
│  │  M365 Agents SDK → MAF Agent → Azure OpenAI → Function Tools    │   │
│  └─────────────────────────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                    MICROSOFT GRAPH API                                 │
│  OneDrive files accessed with user's delegated permissions             │
└────────────────────────────────────────────────────────────────────────┘
```

**SDK Stack:**
- **M365 Agents SDK** (`Microsoft.Agents.Hosting.AspNetCore`) - Bot/Teams messaging infrastructure
- **Microsoft Agents Framework (MAF)** (`Microsoft.Agents.AI`) - AI agent orchestration with function tools

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
- **[Local Development & Testing](OneDriveAgent/README.md#local-development)** - Build, run, and debug locally
- **[Dev Tunnels for Debugging](OneDriveAgent/README.md#local-testing-with-dev-tunnels)** - Test with Teams using dev tunnels
- Token flow explanations
- Troubleshooting guide

## Utility Scripts

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

## License

See [LICENSE](LICENSE) for details.
