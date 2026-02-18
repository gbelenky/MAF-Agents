# OneDrive Agent - Local Development

This document covers local development and debugging. For deployment instructions, see the [main README](../README.md).

## Local Development

### Configure appsettings.Development.json

Copy the template and fill in values:

```bash
cp appsettings.Development.json.template appsettings.Development.json
```

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

> **Note:** Get a client secret from the admin handoff file (`01-admin-output-*.txt`) or Entra ID > App registrations > Agent Identity > Certificates & secrets.

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
# Should return {"status":"healthy",...}
```

## Local Testing with Dev Tunnels

To test the bot locally with Teams, expose your local server using dev tunnels.

### Prerequisites

1. Install the dev tunnels CLI:
   ```bash
   # Windows (winget)
   winget install Microsoft.devtunnel

   # macOS (Homebrew)
   brew install --cask devtunnel
   ```

2. Login to dev tunnels:
   ```bash
   devtunnel user login
   ```

### Create a Persistent Dev Tunnel

```bash
# Create a persistent tunnel with anonymous access (only needed once)
devtunnel create --name onedrive-bot --allow-anonymous

# Add a port mapping for your local bot (port 5001)
devtunnel port create onedrive-bot --port-number 5001 --protocol https
```

### Start the Tunnel

```bash
# Start the tunnel (run this in a separate terminal)
devtunnel host onedrive-bot

# Output will show the tunnel URL, e.g.:
# Connect via browser: https://abc123.devtunnels.ms
```

### Update the Bot Messaging Endpoint

```bash
ENV_NAME=$(azd env get-value AZURE_ENV_NAME)
TUNNEL_URL="https://<your-tunnel-id>.devtunnels.ms"  # From devtunnel host output

az bot update \
    --name "bot-${ENV_NAME}" \
    --resource-group "rg-${ENV_NAME}" \
    --endpoint "${TUNNEL_URL}/api/messages"
```

### Run and Debug Locally

1. Start the dev tunnel in one terminal:
   ```bash
   devtunnel host onedrive-bot
   ```

2. Run the bot in another terminal (or VS Code debugger):
   ```bash
   cd OneDriveAgent
   dotnet run
   ```

3. Open Teams and chat with your bot - requests route to your local machine

### Restore Production Endpoint

After debugging, restore the Azure endpoint:

```bash
ENV_NAME=$(azd env get-value AZURE_ENV_NAME)
APP_URL=$(az webapp show --name "app-${ENV_NAME}" --resource-group "rg-${ENV_NAME}" --query "defaultHostName" -o tsv)

az bot update \
    --name "bot-${ENV_NAME}" \
    --resource-group "rg-${ENV_NAME}" \
    --endpoint "https://${APP_URL}/api/messages"
```

## Troubleshooting

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| "Token exchange failed" | FIC not created | Run `03-admin-create-fic.sh` |
| "AADSTS65001: Consent required" | Admin consent not granted | Re-run `01-admin-create-apps.sh` |
| "Invalid audience" | Wrong scope in token request | Check `access_as_user` scope on app |
| Health endpoint returns error | App not deployed correctly | Run `azd deploy api` |
| Bot not responding in Teams | Wait after deployment | Wait 2-5 minutes for propagation |

### Verify FIC Configuration

```bash
az ad app federated-credential list --id <agent-identity-client-id>
```

### Check Bot OAuth Connection

```bash
az bot authsetting show \
  --name bot-<env> \
  --resource-group rg-<env> \
  --setting-name graph-connection \
  --query "properties.{tokenExchangeUrl:tokenExchangeUrl,clientId:clientId}"
```

### View App Service Logs

```bash
az webapp log tail --name app-<env> --resource-group rg-<env>
```
