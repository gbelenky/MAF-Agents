# Deployment Scripts

This folder contains scripts for deploying the Fabric Data Agent Teams Bot with separation between **Entra Admin** and **Developer** roles.

## Quick Reference

| Script | Role | Purpose |
|--------|------|---------|
| `00-admin-cleanup.sh` | Admin | Delete app registration (optional) |
| `01-admin-create-apps.sh` | Admin | Create Entra app registration |
| `02-dev-generate-handoff.sh` | Developer | Generate handoff file for admin |
| `03-admin-bot-oauth.sh` | Admin | Create Bot OAuth connection |
| `04-dev-teams-manifest.sh` | Developer | Generate Teams app package |
| `cleanup-deploy.sh` | Admin/Dev | Full cleanup (RG + app + azd env) |

## Handoff Files

Scripts communicate via handoff files in the `handoff/` folder:

| File | From | To | Contains |
|------|------|-----|----------|
| `01-admin-output-{env}.txt` | Admin | Developer | Bot Client ID, Tenant ID |
| `02-dev-handoff-{env}.txt` | Developer | Admin | Resource Group, Bot Name |

## Deployment Workflow

### Admin Step 1: Create App Registration
```bash
bash scripts/01-admin-create-apps.sh --prefix fabricagent

# Output: handoff/01-admin-output-fabricagent-*.txt
# → Send to Developer (securely)
```

### Developer Step 2: Deploy Infrastructure
```bash
# Get BOT_CLIENT_ID from admin output file
azd env new fabricagent
azd env set BOT_CLIENT_ID "<BOT_CLIENT_ID from admin file>"
azd env set FABRIC_WORKSPACE_ID "<your-fabric-workspace-id>"
azd env set FABRIC_AGENT_ITEM_ID "<your-fabric-agent-id>"
azd up

# Generate handoff for admin
bash scripts/02-dev-generate-handoff.sh
# Output: handoff/02-dev-handoff-fabricagent.txt
# → Send to Admin (securely)
```

### Admin Step 3: Configure Bot OAuth
```bash
# Using handoff file from Developer
bash scripts/03-admin-bot-oauth.sh \
  --handoff-file /path/to/02-dev-handoff-fabricagent.txt

# Notify Developer when complete
```

This script automatically:
- Configures SSO (Application ID URI, access_as_user scope, pre-authorized Teams clients)
- Adds required Fabric API permissions (DataAgent.Execute.All, MLModel.Execute.All)
- Grants admin consent for Fabric API
- Creates client secret and OAuth connection

### Developer Step 4: Teams Manifest
```bash
bash scripts/04-dev-teams-manifest.sh
# Upload teams-manifest/*.zip to Teams Admin Center
```

## Script Help

Each script supports `--help`:
```bash
bash scripts/01-admin-create-apps.sh --help
bash scripts/03-admin-bot-oauth.sh --help
```

## Cleanup

### Delete Everything (Full Reset)
```bash
# Removes: Resource group + App registration + azd environment
bash scripts/cleanup-deploy.sh --env fabricagent
```

### Delete App Registration Only
```bash
# Admin: Remove just the Entra app registration
bash scripts/00-admin-cleanup.sh --prefix fabricagent
```
