#!/bin/bash
# =============================================================================
# STEP 1: Create Bot App Registration
# =============================================================================
# Purpose: Create a Microsoft Entra app registration for the Teams bot
# Output: Bot App ID and Password for azd deployment
#
# Prerequisites:
#   - Azure CLI installed and logged in
#   - Permissions to create app registrations in your tenant
#
# Usage:
#   bash scripts/01-create-app-registration.sh --name <bot-name>
#
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

BOT_NAME=""
SHOW_HELP=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --name)
            BOT_NAME="$2"
            shift 2
            ;;
        --help|-h)
            SHOW_HELP=true
            shift
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

if [ "$SHOW_HELP" = true ]; then
    echo "Usage: $0 --name <bot-name>"
    echo ""
    echo "Options:"
    echo "  --name <name>   Name for the bot app registration (required)"
    echo "  --help, -h      Show this help message"
    echo ""
    echo "Example:"
    echo "  $0 --name streaming-bot"
    exit 0
fi

if [ -z "$BOT_NAME" ]; then
    echo -e "${RED}Error: --name is required${NC}"
    echo "Usage: $0 --name <bot-name>"
    exit 1
fi

echo ""
echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     Teams Streaming Bot - Create App Registration            ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check Azure CLI login
echo -e "${BLUE}Checking Azure CLI login...${NC}"
if ! az account show &> /dev/null; then
    echo -e "${RED}Not logged in. Run 'az login' first.${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Azure CLI authenticated${NC}"
echo ""

APP_DISPLAY_NAME="${BOT_NAME}-StreamingBot"

# Check if app already exists
echo -e "${BLUE}Checking for existing app registration...${NC}"
EXISTING_APP_ID=$(az ad app list --filter "displayName eq '${APP_DISPLAY_NAME}'" --query "[0].appId" -o tsv 2>/dev/null || echo "")

if [ -n "$EXISTING_APP_ID" ]; then
    echo -e "${YELLOW}⚠ App registration '${APP_DISPLAY_NAME}' already exists: $EXISTING_APP_ID${NC}"
    read -p "Delete and recreate? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Deleting existing app..."
        az ad app delete --id "$EXISTING_APP_ID"
        echo -e "${GREEN}✓ Existing app deleted${NC}"
    else
        echo "Keeping existing app. Exiting."
        exit 0
    fi
fi

# Create app registration (SingleTenant for M365 Agents SDK with MSAL)
echo ""
echo -e "${BLUE}Creating app registration: ${APP_DISPLAY_NAME}${NC}"
APP_ID=$(az ad app create \
    --display-name "$APP_DISPLAY_NAME" \
    --sign-in-audience "AzureADMyOrg" \
    --query "appId" -o tsv)

echo -e "${GREEN}✓ App created: $APP_ID${NC}"

# Create service principal (required for MSAL authentication)
echo ""
echo -e "${BLUE}Creating service principal...${NC}"
az ad sp create --id "$APP_ID" > /dev/null 2>&1 || echo "Service principal may already exist"
echo -e "${GREEN}✓ Service principal created${NC}"

# Create client secret
echo ""
echo -e "${BLUE}Creating client secret...${NC}"
SECRET_RESULT=$(az ad app credential reset \
    --id "$APP_ID" \
    --display-name "azd-deployment" \
    --years 2 \
    --query "{password:password}" -o json)

BOT_PASSWORD=$(echo "$SECRET_RESULT" | jq -r '.password')
echo -e "${GREEN}✓ Client secret created${NC}"

# Get tenant ID
TENANT_ID=$(az account show --query "tenantId" -o tsv)

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     App Registration Created Successfully!                    ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "App Display Name:  ${APP_DISPLAY_NAME}"
echo -e "Application ID:    ${BLUE}${APP_ID}${NC}"
echo -e "Tenant ID:         ${TENANT_ID}"
echo ""
echo -e "${YELLOW}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║  IMPORTANT: Save the password below - it won't be shown again ║${NC}"
echo -e "${YELLOW}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "Client Secret:     ${RED}${BOT_PASSWORD}${NC}"
echo ""

# Save to output file in project root
OUTPUT_FILE="${PROJECT_ROOT}/bot-credentials-${BOT_NAME}.txt"
cat > "$OUTPUT_FILE" << EOF
# Teams Streaming Bot - App Registration Credentials
# Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
# 
# App Type: SingleTenant (AzureADMyOrg)
# Service Principal: Created (required for MSAL authentication)
#
# KEEP THIS FILE SECURE - Contains secrets!
# Add to .gitignore to prevent accidental commits

BOT_NAME=${BOT_NAME}
BOT_ID=${APP_ID}
BOT_PASSWORD=${BOT_PASSWORD}
TENANT_ID=${TENANT_ID}

# Next steps:
# 1. Set azd environment variables:
#    azd env new ${BOT_NAME}
#    azd env set BOT_ID "${APP_ID}"
#    azd env set BOT_PASSWORD "${BOT_PASSWORD}"
#    azd env set AZURE_OPENAI_ENDPOINT "https://your-resource.openai.azure.com/"
#    azd env set AZURE_OPENAI_DEPLOYMENT_NAME "gpt-4.1-mini"
#
# 2. Deploy to Azure:
#    azd up
#
# 3. Grant Managed Identity access to Azure OpenAI (use PowerShell, not Git Bash!):
#    \$MI_ID = az webapp identity show --name app-<id> --resource-group rg-${BOT_NAME} --query principalId -o tsv
#    az role assignment create --assignee-object-id \$MI_ID --assignee-principal-type ServicePrincipal --role "Cognitive Services OpenAI User" --scope "<azure-openai-resource-id>"
#
# 4. Generate Teams manifest:
#    bash scripts/03-teams-manifest.sh
EOF

chmod 600 "$OUTPUT_FILE"
echo -e "${GREEN}✓ Credentials saved to: ${OUTPUT_FILE}${NC}"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "  1. Create azd environment and set variables:"
echo "     azd env new $BOT_NAME"
echo "     azd env set BOT_ID \"$APP_ID\""
echo "     azd env set BOT_PASSWORD \"$BOT_PASSWORD\""
echo "     azd env set AZURE_OPENAI_ENDPOINT \"https://your-resource.openai.azure.com/\""
echo "     azd env set AZURE_OPENAI_DEPLOYMENT_NAME \"gpt-4.1-mini\""
echo ""
echo "  2. Deploy to Azure:"
echo "     azd up"
echo ""
echo "  3. Grant Managed Identity access to Azure OpenAI (use PowerShell!):"
echo "     az role assignment create --assignee-object-id <MI_ID> --assignee-principal-type ServicePrincipal --role \"Cognitive Services OpenAI User\" --scope \"<aoai-resource-id>\""
echo ""
echo "  4. Generate Teams manifest:"
echo "     bash scripts/03-teams-manifest.sh"
echo ""
echo "  5. Upload teams-manifest/${BOT_NAME^}.zip to Teams"
echo ""
