# Deployment Scripts

This folder contains scripts for deploying the OneDrive Agent with separation between **Entra Admin** and **Developer** roles.

## Quick Reference

| Script | Role | Purpose |
|--------|------|---------|
| `01-admin-create-apps.sh` | Admin | Create Entra app registration |
| `02-dev-generate-handoff.sh` | Developer | Generate handoff file for admin |
| `03-admin-create-fic.sh` | Admin | Create Federated Identity Credential |
| `04-admin-bot-oauth.sh` | Admin | Create Bot OAuth connection |
| `05-dev-teams-manifest.sh` | Developer | Generate Teams app package |

## Handoff Files

Scripts communicate via handoff files in the `handoff/` folder:

| File | From | To | Contains |
|------|------|-----|----------|
| `01-admin-output-{env}.txt` | Admin | Developer | App ID, Tenant ID |
| `02-dev-handoff-{env}.txt` | Developer | Admin | MI ID, Resource Group, Bot Name |

## Deployment Workflow

### Admin Step 1: Create App Registration
```bash
bash scripts/01-admin-create-apps.sh --prefix myagent

# Output: handoff/01-admin-output-myagent.txt
# → Send to Developer (securely)
```

### Developer Step 2: Deploy Infrastructure
```bash
# Get APP_ID from admin output file
azd env new myagent
azd env set AGENT_IDENTITY_CLIENT_ID "<APP_ID from admin file>"
azd up

# Generate handoff for admin
bash scripts/02-dev-generate-handoff.sh
# Output: handoff/02-dev-handoff-myagent.txt
# → Send to Admin (securely)
```

### Admin Step 3-4: Configure FIC and OAuth
```bash
# Using handoff file from Developer
bash scripts/03-admin-create-fic.sh \
  --handoff-file /path/to/02-dev-handoff-myagent.txt

bash scripts/04-admin-bot-oauth.sh \
  --handoff-file /path/to/02-dev-handoff-myagent.txt

# Notify Developer when complete
```

### Developer Step 5-6: Teams Manifest
```bash
bash scripts/05-dev-teams-manifest.sh
# Upload teams-manifest/*.zip to Teams Admin Center
```

## Script Help

Each script supports `--help`:
```bash
bash scripts/01-admin-create-apps.sh --help
bash scripts/03-admin-create-fic.sh --help
bash scripts/04-admin-bot-oauth.sh --help
```

## Alternative: Explicit Parameters

If not using handoff files, pass parameters directly:
```bash
bash scripts/03-admin-create-fic.sh \
  --agent-identity-id <APP_ID> \
  --mi-client-id <MI_CLIENT_ID>

bash scripts/04-admin-bot-oauth.sh \
  --bot-app-id <APP_ID> \
  --resource-group rg-myagent \
  --bot-name bot-myagent
```
