---
description: troubleshoot and deploy 
# applyTo: 'troubleshoot and deploy ' # when provided, instructions will automatically be added to the request context when the pattern matches an attached file
---

## Deployment Guidelines

Always use **azd (Azure Developer CLI)** for deployment. It provides a streamlined experience for deploying and managing your applications on Azure.

### Deployment Commands
```bash
azd up                    # Full deployment (provision + deploy)
azd provision             # Infrastructure only
azd deploy                # Code only
azd env get-values        # Show all environment values
```

### Configuration Consistency
- Always be consistent between documentation, configuration, and deployment
- If any settings change in Azure Portal or CLI, update the corresponding:
  - `infra/*.bicep` files
  - `appsettings.json` / `appsettings.Development.json.template`
  - `README.md` documentation

## Monitoring

Always use **Application Insights** to monitor your application:
- Check Live Metrics for real-time telemetry
- Review Failures blade for exceptions
- Use Transaction Search for request tracing
- Set up alerts for critical metrics

## Troubleshooting

### Architecture Dependencies
When troubleshooting, always follow the architecture dependency chain:
1. **Client (Teams)** → 2. **Bot Service** → 3. **App Service API** → 4. **Azure OpenAI** → 5. **Microsoft Graph**

### Common Issues

#### OAuth/SSO Issues
1. Check Teams OAuth connection in Bot Service → Configuration → OAuth Connection Settings
2. Verify client secret is valid and not expired
3. Verify pre-authorized clients include Teams app IDs
4. Check `tokenExchangeUrl` matches the identifier URI format: `api://botid-{app-id}`

#### Token Flow Issues
- **Teams Bot**: Token from Bot Token Service is already a Graph token (no OBO needed)
- **API-only mode**: Requires OBO exchange from user token to Graph token
- Check logs for `AADSTS` errors which indicate Entra ID issues

#### Deployment Issues
```bash
# View app logs
az webapp log tail --name app-{env} --resource-group rg-{env}

# Download logs
az webapp log download --name app-{env} --resource-group rg-{env} --log-file logs.zip

# Check app health
curl https://app-{env}.azurewebsites.net/health
```

#### App Settings Issues
```bash
# List all settings
az webapp config appsettings list --name app-{env} --resource-group rg-{env} --output table

# Set a specific setting
az webapp config appsettings set --name app-{env} --resource-group rg-{env} --settings "KEY=value"

# Restart app after settings change
az webapp restart --name app-{env} --resource-group rg-{env}
```

### Key Error Codes
| Error | Meaning | Solution |
|-------|---------|----------|
| `AADSTS50013` | Token signature validation failed | Token being passed is already exchanged; don't do OBO |
| `AADSTS65001` | Consent not granted | Run `az ad app permission admin-consent` |
| `AADSTS700016` | App not found in tenant | Check app ID and tenant ID match |
| `invalid_client` | Client secret expired or wrong | Create new secret, update OAuth connection |

## Script Reference

| Script | Who | Purpose |
|--------|-----|---------|
| `01-admin-create-apps.sh` | Admin | Create app registrations |
| `02-dev-generate-handoff.sh` | Developer | Generate handoff file for admin |
| `03-admin-create-fic.sh` | Admin | Create FIC after deployment |
| `04-admin-bot-oauth.sh` | Admin | Configure bot OAuth connection |
| `05-dev-teams-manifest.sh` | Developer | Generate Teams app manifest |
| `00-admin-cleanup.sh` | Admin | Delete app registrations (reset) |
| `cleanup-deploy.sh` | Developer | Full cleanup (Azure + Entra + azd) |