# Deployment Scripts

This folder contains scripts for deploying the Teams Streaming Bot with separation between **Admin** and **Developer** roles.

## Quick Reference

| Script | Role | Purpose |
|--------|------|---------|
| `01-admin-create-app-registration.sh` | Admin | Create Entra app registration |
| `02-dev-generate-handoff.sh` | Developer | Generate handoff file for admin |
| `03-admin-grant-openai-rbac.sh` | Admin | Grant Azure OpenAI access |
| `04-dev-teams-manifest.sh` | Developer | Generate Teams app package |
| `cleanup.sh` | Developer | Remove all deployment resources |

## Handoff Files

Scripts communicate via handoff files in the `handoff/` folder:

| File | From | To | Contains |
|------|------|-----|----------|
| `bot-credentials-{env}.txt` | Admin | Developer | App ID, Password, Tenant ID |
| `02-dev-handoff-{env}.txt` | Developer | Admin | MI Principal ID, Resource Group |

## Prerequisites

- [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli) - logged in with `az login`
- [Azure Developer CLI (azd)](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd)
- [PowerShell](https://docs.microsoft.com/powershell/) - for RBAC commands (avoids Git Bash path issues)

## Deployment Workflow

```
┌── ADMIN ──────────────────────────────────────────────────────────┐
│  STEP 1: Create App Registration                                 │
│  bash scripts/01-admin-create-app-registration.sh --name mybot   │
│  ↳ Creates: SingleTenant app + Service Principal                 │
│  ↳ Output: bot-credentials-mybot.txt                             │
│  ↳ Share credentials file with Developer (securely)              │
└───────────────────────────────────────────────────────────────────┘
                              ↓
┌── DEVELOPER ──────────────────────────────────────────────────────┐
│  STEP 2a: Deploy to Azure                                        │
│  azd env new mybot                                                │
│  azd env set BOT_ID "<from-credentials-file>"                     │
│  azd env set BOT_PASSWORD "<from-credentials-file>"               │
│  azd env set BOT_TENANT_ID "<from-credentials-file>"              │
│  azd env set AZURE_OPENAI_ENDPOINT "https://xxx.openai.azure.com/"│
│  azd env set AZURE_OPENAI_DEPLOYMENT_NAME "gpt-4.1-mini"          │
│  azd up                                                           │
│                                                                   │
│  STEP 2b: Generate Handoff                                        │
│  bash scripts/02-dev-generate-handoff.sh                          │
│  ↳ Output: handoff/02-dev-handoff-mybot.txt                       │
│  ↳ Share with Admin                                               │
└───────────────────────────────────────────────────────────────────┘
                              ↓
┌── ADMIN ──────────────────────────────────────────────────────────┐
│  STEP 3: Grant Azure OpenAI Access                               │
│  bash scripts/03-admin-grant-openai-rbac.sh \                    │
│    --handoff-file handoff/02-dev-handoff-mybot.txt \             │
│    --openai-rg rg-openai --openai-account my-aoai                │
│  ↳ Notify Developer when complete                                │
└───────────────────────────────────────────────────────────────────┘
                              ↓
┌── DEVELOPER ──────────────────────────────────────────────────────┐
│  STEP 4: Generate Teams Manifest                                 │
│  bash scripts/04-dev-teams-manifest.sh                            │
│  ↳ Output: teams-manifest/Mybot.zip                               │
└───────────────────────────────────────────────────────────────────┘
                              ↓
┌── TEAMS ADMIN ────────────────────────────────────────────────────┐
│  STEP 5: Install in Teams                                        │
│  Upload teams-manifest/Mybot.zip to Teams Admin Center           │
│  OR Developer sideloads for testing                              │
└───────────────────────────────────────────────────────────────────┘
```

## Detailed Steps

### Step 1: Create App Registration (Admin)

```bash
bash scripts/01-admin-create-app-registration.sh --name mybot
```

This creates:
- **SingleTenant** Microsoft Entra app registration (`AzureADMyOrg`)
- **Service Principal** (required for MSAL authentication)
- Client secret for azd deployment (2-year validity)
- Credentials file: `bot-credentials-mybot.txt`

> **Important:** The service principal is required! Without it, MSAL returns `AADSTS7000229` error.

Share `bot-credentials-mybot.txt` with the Developer (securely).

### Step 2: Deploy to Azure (Developer)

```bash
# Create environment and set variables from credentials file
azd env new mybot
azd env set BOT_ID "<from-credentials-file>"
azd env set BOT_PASSWORD "<from-credentials-file>"
azd env set BOT_TENANT_ID "<from-credentials-file>"
azd env set AZURE_OPENAI_ENDPOINT "https://your-resource.openai.azure.com/"
azd env set AZURE_OPENAI_DEPLOYMENT_NAME "gpt-4.1-mini"

# Deploy
azd up

# Generate handoff file for Admin
bash scripts/02-dev-generate-handoff.sh
```

The handoff script creates `handoff/02-dev-handoff-mybot.txt` with the Managed Identity ID. Share this with the Admin.

Verify deployment:
```bash
curl https://app-<id>.azurewebsites.net/health
```

### Step 3: Grant Azure OpenAI Access (Admin)

```bash
bash scripts/03-admin-grant-openai-rbac.sh \
  --handoff-file handoff/02-dev-handoff-mybot.txt \
  --openai-rg rg-openai \
  --openai-account my-aoai-resource
```

> **Note:** This script uses PowerShell internally to avoid Git Bash path issues with `/subscriptions/...` paths.

Alternative - manual command in PowerShell:

```powershell
# PowerShell
az role assignment create `
  --assignee-object-id "<managed-identity-principal-id>" `
  --assignee-principal-type ServicePrincipal `
  --role "Cognitive Services OpenAI User" `
  --scope "/subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.CognitiveServices/accounts/<aoai-resource>"
```

### Step 4: Generate Teams Manifest (Developer)

```bash
bash scripts/04-dev-teams-manifest.sh
```

This creates `teams-manifest/Mybot.zip` containing:
- `manifest.json` - Teams app manifest with your bot ID
- `color.png` - Color icon (192x192)
- `outline.png` - Outline icon (32x32)

### Step 5: Install in Teams

**Option A: Teams Admin Center (recommended)**
1. Go to https://admin.teams.microsoft.com
2. Navigate to Teams apps > Manage apps
3. Click "Upload new app"
4. Select `teams-manifest/Mybot.zip`

**Option B: Sideload (for testing)**
1. Open Teams
2. Go to Apps > Manage your apps
3. Click "Upload an app" > "Upload a custom app"
4. Select `teams-manifest/Mybot.zip`

## Cleanup

Remove all resources for a deployment:

```bash
bash scripts/cleanup.sh --env mybot
```

This deletes:
- Azure resource group and all resources
- App registration
- azd environment
- Local credential files

## Script Help

Each script supports `--help`:
```bash
bash scripts/01-create-app-registration.sh --help
bash scripts/02-deploy.sh --help
bash scripts/03-teams-manifest.sh --help
bash scripts/cleanup.sh --help
```

## Troubleshooting

### Bot not responding in Teams

1. Check the health endpoint:
   ```bash
   curl https://app-mybot.azurewebsites.net/health
   ```

2. Check Bot Service is registered:
   - Azure Portal > Bot Services > bot-mybot

3. Verify Teams channel is enabled:
   - Bot Service > Channels > Microsoft Teams

4. Check App Service logs:
   ```bash
   az webapp log tail --name app-mybot --resource-group rg-mybot
   ```

### Azure OpenAI errors

1. Verify endpoint and deployment name in azd environment:
   ```bash
   azd env get-value AZURE_OPENAI_ENDPOINT
   azd env get-value AZURE_OPENAI_DEPLOYMENT_NAME
   ```

2. Check managed identity has Cognitive Services User role on OpenAI resource

### Manifest validation errors

1. Ensure icon files exist:
   - `appManifest/color.png` (192x192 PNG)
   - `appManifest/outline.png` (32x32 PNG, transparent background)

2. Validate manifest JSON schema:
   - Check bot ID matches app registration
   - Check domain matches App Service hostname
