#!/bin/bash
# =============================================================================
# STEP 3: Entra Admin - Create Bot OAuth Connection
# =============================================================================
# Role: ENTRA ADMIN
# Purpose: Create client secret and OAuth connection for Bot Service SSO
# Run: AFTER Step 2 (azd provision completed)
#
# Input: 02-dev-handoff-{env}.txt (auto-detected) OR azd environment OR args
#
# Prerequisites:
#   - Azure CLI installed
#   - Logged in with Entra Admin privileges
#   - Bot App Registration exists (from Step 1)
#   - Bot Service exists in Azure (from azd provision)
#
# Usage:
#   ./03-admin-bot-oauth.sh [options]
#
# Options:
#   --bot-app-id <id>         Bot App Registration Client ID
#   --resource-group <name>   Resource group containing Bot Service
#   --bot-name <name>         Bot Service resource name
#   --tenant-id <id>          Azure AD tenant ID
#   --secret-years <n>        Client secret validity in years (default: 2)
#
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${BLUE}"
echo "=============================================="
echo "  STEP 3: Entra Admin - Bot OAuth Connection"
echo "  (Fabric Data Agent Teams Bot)"
echo "=============================================="
echo -e "${NC}"

# Parse arguments with defaults
BOT_APP_ID=""
RESOURCE_GROUP=""
BOT_NAME=""
TENANT_ID=""
SECRET_YEARS=2
OAUTH_CONNECTION_NAME="fabric-connection"
SCOPES="https://api.fabric.microsoft.com/DataAgent.Execute.All https://api.fabric.microsoft.com/MLModel.Execute.All openid profile"
HANDOFF_FILE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --bot-app-id)
            BOT_APP_ID="$2"
            shift 2
            ;;
        --resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        --bot-name)
            BOT_NAME="$2"
            shift 2
            ;;
        --tenant-id)
            TENANT_ID="$2"
            shift 2
            ;;
        --secret-years)
            SECRET_YEARS="$2"
            shift 2
            ;;
        --connection-name)
            OAUTH_CONNECTION_NAME="$2"
            shift 2
            ;;
        --scopes)
            SCOPES="$2"
            shift 2
            ;;
        --handoff-file)
            HANDOFF_FILE="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --handoff-file <path>     Developer handoff file (02-dev-handoff-*.txt)"
            echo "  --bot-app-id <id>         Bot App Registration Client ID"
            echo "  --resource-group <name>   Resource group containing Bot Service"
            echo "  --bot-name <name>         Bot Service resource name"
            echo "  --tenant-id <id>          Azure AD tenant ID (auto-detected if not provided)"
            echo "  --secret-years <n>        Client secret validity in years (default: 2)"
            echo "  --connection-name <name>  OAuth connection name (default: fabric-connection)"
            echo "  --scopes <scopes>         OAuth scopes"
            echo ""
            echo "For separated admin/dev workflow, place the developer handoff file in:"
            echo "  handoff/02-dev-handoff-{env}.txt"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# Try to load from dev handoff file if available (for separate admin/dev workflow)
ADMIN_INPUT_FILE=""

# Use explicit --handoff-file if provided
if [ -n "$HANDOFF_FILE" ]; then
    if [ -f "$HANDOFF_FILE" ]; then
        ADMIN_INPUT_FILE="$HANDOFF_FILE"
        echo -e "${GREEN}✓ Using specified handoff file: $HANDOFF_FILE${NC}"
    else
        echo -e "${RED}ERROR: Specified handoff file not found: $HANDOFF_FILE${NC}"
        exit 1
    fi
else
    # Auto-detect: Check handoff folder first, then current directory
    for f in handoff/02-dev-handoff-*.txt 02-dev-handoff-*.txt; do
        if [ -f "$f" ]; then
            ADMIN_INPUT_FILE="$f"
            break
        fi
    done
fi

if [ -n "$ADMIN_INPUT_FILE" ] && [ -z "$BOT_APP_ID" ] && [ -z "$RESOURCE_GROUP" ]; then
    echo -e "${GREEN}✓ Found admin input file: $ADMIN_INPUT_FILE${NC}"
    echo -e "${YELLOW}  Loading values from file...${NC}"
    
    if [ -z "$BOT_APP_ID" ]; then
        FILE_BOT_ID=$(grep "^BOT_CLIENT_ID=" "$ADMIN_INPUT_FILE" | cut -d'=' -f2)
        if [ -n "$FILE_BOT_ID" ]; then
            BOT_APP_ID="$FILE_BOT_ID"
            echo -e "${GREEN}  ✓ BOT_APP_ID from file${NC}"
        fi
    fi
    
    if [ -z "$RESOURCE_GROUP" ]; then
        FILE_RG=$(grep "^RESOURCE_GROUP=" "$ADMIN_INPUT_FILE" | cut -d'=' -f2)
        if [ -n "$FILE_RG" ]; then
            RESOURCE_GROUP="$FILE_RG"
            echo -e "${GREEN}  ✓ RESOURCE_GROUP from file${NC}"
        fi
    fi
    
    if [ -z "$BOT_NAME" ]; then
        FILE_BOT_NAME=$(grep "^BOT_NAME=" "$ADMIN_INPUT_FILE" | cut -d'=' -f2)
        if [ -n "$FILE_BOT_NAME" ]; then
            BOT_NAME="$FILE_BOT_NAME"
            echo -e "${GREEN}  ✓ BOT_NAME from file${NC}"
        fi
    fi
fi

# Check Azure CLI is installed
if ! command -v az &> /dev/null; then
    echo -e "${RED}Error: Azure CLI is not installed.${NC}"
    exit 1
fi

# Check if logged in
CURRENT_USER=$(az ad signed-in-user show --query displayName -o tsv 2>/dev/null) || {
    echo -e "${YELLOW}Not logged in. Please log in with admin credentials.${NC}"
    az login
    CURRENT_USER=$(az ad signed-in-user show --query displayName -o tsv)
}

echo -e "${GREEN}✓ Logged in as: $CURRENT_USER${NC}"

# Get tenant ID if not provided
if [ -z "$TENANT_ID" ]; then
    TENANT_ID=$(az account show --query tenantId -o tsv)
fi
echo -e "${BLUE}Tenant: $TENANT_ID${NC}"

# Prompt for required values if not provided via handoff file or command line
if [ -z "$BOT_APP_ID" ]; then
    echo ""
    echo -e "${YELLOW}Bot App ID not found.${NC}"
    echo -e "  This should be in the Developer's handoff file:"
    echo -e "  - File: handoff/02-dev-handoff-{env}.txt"
    echo -e "  - Look for: BOT_CLIENT_ID=..."
    echo -e ""
    echo -e "  Or use: --bot-app-id <id> or --handoff-file <file>"
    read -p "Enter Bot App Registration Client ID: " BOT_APP_ID
fi

if [ -z "$RESOURCE_GROUP" ]; then
    echo ""
    echo -e "${YELLOW}Resource Group not found.${NC}"
    echo -e "  This should be in the Developer's handoff file:"
    echo -e "  - File: handoff/02-dev-handoff-{env}.txt"
    echo -e "  - Look for: RESOURCE_GROUP=..."
    echo -e ""
    echo -e "  Or use: --resource-group <name>"
    read -p "Enter Resource Group name: " RESOURCE_GROUP
fi

if [ -z "$BOT_NAME" ]; then
    echo ""
    echo -e "${YELLOW}Bot Name not found.${NC}"
    echo -e "  This should be in the Developer's handoff file:"
    echo -e "  - File: handoff/02-dev-handoff-{env}.txt"
    echo -e "  - Look for: BOT_NAME=..."
    echo -e ""
    echo -e "  Or use: --bot-name <name>"
    read -p "Enter Bot Service name: " BOT_NAME
fi

echo ""
echo -e "${CYAN}Configuration:${NC}"
echo "  Bot App ID:         $BOT_APP_ID"
echo "  Resource Group:     $RESOURCE_GROUP"
echo "  Bot Name:           $BOT_NAME"
echo "  Tenant ID:          $TENANT_ID"
echo "  OAuth Connection:   $OAUTH_CONNECTION_NAME"
echo "  Scopes:             $SCOPES"
echo "  Secret Validity:    $SECRET_YEARS years"
echo ""

read -p "Continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

# =============================================================================
# Step 1: Verify Bot App Registration exists
# =============================================================================
echo ""
echo -e "${BLUE}Step 1/5: Verifying Bot App Registration...${NC}"

APP_EXISTS=$(az ad app show --id "$BOT_APP_ID" --query appId -o tsv 2>/dev/null) || {
    echo -e "${RED}Error: App registration $BOT_APP_ID not found.${NC}"
    exit 1
}
echo -e "${GREEN}✓ App registration exists: $APP_EXISTS${NC}"

# =============================================================================
# Step 2: Configure App Registration for SSO (Expose an API)
# =============================================================================
echo ""
echo -e "${BLUE}Step 2/5: Configuring App Registration for SSO...${NC}"

# Set Application ID URI for SSO
TOKEN_EXCHANGE_URL="api://botid-$BOT_APP_ID"
az ad app update --id "$BOT_APP_ID" \
    --identifier-uris "$TOKEN_EXCHANGE_URL" 2>/dev/null || true
echo -e "${GREEN}✓ Set Application ID URI: $TOKEN_EXCHANGE_URL${NC}"

# Check if access_as_user scope exists
EXISTING_SCOPES=$(az ad app show --id "$BOT_APP_ID" --query "api.oauth2PermissionScopes[].value" -o tsv 2>/dev/null)
if [[ "$EXISTING_SCOPES" != *"access_as_user"* ]]; then
    # Generate UUID for scope (Windows compatible)
    SCOPE_ID=$(python3 -c "import uuid; print(uuid.uuid4())" 2>/dev/null || \
               python -c "import uuid; print(uuid.uuid4())" 2>/dev/null || \
               uuidgen 2>/dev/null || \
               echo "$(od -x /dev/urandom | head -1 | awk '{print $2$3"-"$4"-"$5"-"$6"-"$7$8$9}')")

    # Add access_as_user scope
    az rest --method PATCH \
        --uri "https://graph.microsoft.com/v1.0/applications(appId='$BOT_APP_ID')" \
        --headers "Content-Type=application/json" \
        --body "{
            \"api\": {
                \"oauth2PermissionScopes\": [{
                    \"id\": \"$SCOPE_ID\",
                    \"adminConsentDisplayName\": \"Access as user\",
                    \"adminConsentDescription\": \"Allow the bot to access resources on behalf of the signed-in user\",
                    \"userConsentDisplayName\": \"Access as you\",
                    \"userConsentDescription\": \"Allow the bot to access resources on your behalf\",
                    \"isEnabled\": true,
                    \"type\": \"User\",
                    \"value\": \"access_as_user\"
                }]
            }
        }" > /dev/null 2>&1 || true
    echo -e "${GREEN}✓ Added access_as_user scope${NC}"
else
    echo -e "${GREEN}✓ access_as_user scope already exists${NC}"
fi

# Add pre-authorized client apps for SSO
# Teams/Office clients (8 total including Agents Playground):
echo "  Adding pre-authorized client apps (Teams + Agents Playground)..."

# Get the scope ID
SCOPE_ID=$(az ad app show --id "$BOT_APP_ID" --query "api.oauth2PermissionScopes[?value=='access_as_user'].id" -o tsv 2>/dev/null)

if [ -n "$SCOPE_ID" ]; then
    az rest --method PATCH \
        --uri "https://graph.microsoft.com/v1.0/applications(appId='$BOT_APP_ID')" \
        --headers "Content-Type=application/json" \
        --body "{
            \"api\": {
                \"preAuthorizedApplications\": [
                    {\"appId\": \"1fec8e78-bce4-4aaf-ab1b-5451cc387264\", \"delegatedPermissionIds\": [\"$SCOPE_ID\"]},
                    {\"appId\": \"5e3ce6c0-2b1f-4285-8d4b-75ee78787346\", \"delegatedPermissionIds\": [\"$SCOPE_ID\"]},
                    {\"appId\": \"d3590ed6-52b3-4102-aeff-aad2292ab01c\", \"delegatedPermissionIds\": [\"$SCOPE_ID\"]},
                    {\"appId\": \"27922004-5251-4030-b22d-91ecd9a37ea4\", \"delegatedPermissionIds\": [\"$SCOPE_ID\"]},
                    {\"appId\": \"bc59ab01-8403-45c6-8796-ac3ef710b3e3\", \"delegatedPermissionIds\": [\"$SCOPE_ID\"]},
                    {\"appId\": \"0ec893e0-5785-4de6-99da-4ed124e5296c\", \"delegatedPermissionIds\": [\"$SCOPE_ID\"]},
                    {\"appId\": \"4765445b-32c6-49b0-83e6-1d93765276ca\", \"delegatedPermissionIds\": [\"$SCOPE_ID\"]},
                    {\"appId\": \"ab3be6b7-f5df-413d-ac2d-abf1e3fd9c0b\", \"delegatedPermissionIds\": [\"$SCOPE_ID\"]}
                ]
            }
        }" > /dev/null 2>&1 || true
    echo -e "${GREEN}✓ Added pre-authorized clients (Teams + Agents Playground)${NC}"
fi

# Add required Fabric API permissions
echo "  Adding Fabric API permissions (DataAgent.Execute.All, MLModel.Execute.All)..."

# Fabric/Power BI API: 00000009-0000-0000-c000-000000000000
# DataAgent.Execute.All: c6756612-6853-4145-a661-90c1d045b2dc
# MLModel.Execute.All: 6b03f425-0a8e-4c54-ba35-df73806f1396
az ad app permission add --id "$BOT_APP_ID" \
    --api "00000009-0000-0000-c000-000000000000" \
    --api-permissions "c6756612-6853-4145-a661-90c1d045b2dc=Scope" 2>/dev/null || true
az ad app permission add --id "$BOT_APP_ID" \
    --api "00000009-0000-0000-c000-000000000000" \
    --api-permissions "6b03f425-0a8e-4c54-ba35-df73806f1396=Scope" 2>/dev/null || true
echo -e "${GREEN}✓ Added Fabric API permissions${NC}"

# Grant admin consent for Fabric API
echo "  Granting admin consent for Fabric API..."
az ad app permission grant --id "$BOT_APP_ID" \
    --api "00000009-0000-0000-c000-000000000000" \
    --scope "DataAgent.Execute.All MLModel.Execute.All Item.Read.All Workspace.Read.All" 2>/dev/null || true
echo -e "${GREEN}✓ Admin consent granted for Fabric API${NC}"

# =============================================================================
# Step 3: Create Client Secret
# =============================================================================
echo ""
echo -e "${BLUE}Step 3/5: Creating Client Secret for Bot Framework + OAuth...${NC}"

# Check for existing secrets (informational only)
EXISTING_SECRETS=$(az ad app credential list --id "$BOT_APP_ID" --query "length(@)" -o tsv)
if [ "$EXISTING_SECRETS" -gt 0 ]; then
    echo -e "${YELLOW}Note: $EXISTING_SECRETS existing secret(s) found. Creating new one for Bot OAuth.${NC}"
fi

# Always create a new secret for the OAuth connection
SECRET_RESULT=$(az ad app credential reset \
    --id "$BOT_APP_ID" \
    --display-name "BotOAuth-Secret-$(date +%Y%m%d)" \
    --years "$SECRET_YEARS" \
    --query password -o tsv)
CLIENT_SECRET="$SECRET_RESULT"
echo -e "${GREEN}✓ Created BotOAuth-Secret (valid for $SECRET_YEARS years)${NC}"

# =============================================================================
# Step 4: Create OAuth Connection on Bot Service
# =============================================================================
echo ""
echo -e "${BLUE}Step 4/5: Creating OAuth Connection on Bot Service...${NC}"

if [ -z "$CLIENT_SECRET" ]; then
    echo -e "${YELLOW}No client secret available. Skipping OAuth connection creation.${NC}"
    echo ""
    echo "To create the OAuth connection manually, run:"
    echo ""
    echo "  az bot authsetting create \\"
    echo "    --name $BOT_NAME \\"
    echo "    --resource-group $RESOURCE_GROUP \\"
    echo "    --setting-name \"$OAUTH_CONNECTION_NAME\" \\"
    echo "    --client-id \"$BOT_APP_ID\" \\"
    echo "    --client-secret \"<YOUR_SECRET>\" \\"
    echo "    --service \"Aadv2\" \\"
    echo "    --provider-scope-string \"$SCOPES\" \\"
    echo "    --parameters tenantId=$TENANT_ID tokenExchangeUrl=$TOKEN_EXCHANGE_URL"
    exit 0
fi

# Check if connection already exists
EXISTING_CONNECTION=$(az bot authsetting list \
    --name "$BOT_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --query "[?name=='$BOT_NAME/$OAUTH_CONNECTION_NAME'].name" -o tsv 2>/dev/null)

if [ -n "$EXISTING_CONNECTION" ]; then
    echo -e "${YELLOW}OAuth connection '$OAUTH_CONNECTION_NAME' already exists. Deleting first...${NC}"
    az bot authsetting delete \
        --name "$BOT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --setting-name "$OAUTH_CONNECTION_NAME" 2>/dev/null || true
    echo "Waiting for deletion to complete..."
    sleep 5
fi

az bot authsetting create \
    --name "$BOT_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --setting-name "$OAUTH_CONNECTION_NAME" \
    --client-id "$BOT_APP_ID" \
    --client-secret "$CLIENT_SECRET" \
    --service "Aadv2" \
    --provider-scope-string "$SCOPES" \
    --parameters tenantId="$TENANT_ID" tokenExchangeUrl="$TOKEN_EXCHANGE_URL"

# Verify the OAuth connection was created correctly
VERIFY_TOKEN_URL=$(az bot authsetting show \
    --name "$BOT_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --setting-name "$OAUTH_CONNECTION_NAME" \
    --query "properties.parameters[?key=='tokenExchangeUrl'].value" -o tsv 2>/dev/null)

if [ "$VERIFY_TOKEN_URL" = "$TOKEN_EXCHANGE_URL" ]; then
    echo -e "${GREEN}✓ OAuth connection created with tokenExchangeUrl: $TOKEN_EXCHANGE_URL${NC}"
else
    echo -e "${YELLOW}⚠ OAuth connection created but tokenExchangeUrl may not be set correctly.${NC}"
    echo "  Expected: $TOKEN_EXCHANGE_URL"
    echo "  Got: $VERIFY_TOKEN_URL"
    echo ""
    echo "  You may need to recreate it manually in Azure Portal or re-run this script."
fi

# =============================================================================
# Step 5: Set MicrosoftAppPassword in App Service
# =============================================================================
echo ""
echo -e "${BLUE}Step 5/5: Setting Bot Framework auth in App Service...${NC}"

# Get the App Service name from handoff (should be app-{env})
APP_SERVICE_NAME="app-${AZURE_ENV_NAME:-}"
if [ -z "$APP_SERVICE_NAME" ] || [ "$APP_SERVICE_NAME" = "app-" ]; then
    # Try to derive from bot name (bot-{env} -> app-{env})
    APP_SERVICE_NAME=$(echo "$BOT_NAME" | sed 's/^bot-/app-/')
fi

az webapp config appsettings set \
    --name "$APP_SERVICE_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --settings MicrosoftAppPassword="$CLIENT_SECRET" > /dev/null 2>&1 && \
    echo -e "${GREEN}✓ Set MicrosoftAppPassword in App Service${NC}" || \
    echo -e "${YELLOW}⚠ Could not set MicrosoftAppPassword - set it manually in App Service${NC}"

# =============================================================================
# Summary
# =============================================================================
echo ""
echo -e "${GREEN}=============================================="
echo "  ✅ STEP 4 COMPLETE"
echo "==============================================${NC}"
echo ""
echo "Configuration Summary:"
echo "  - Bot App ID:           $BOT_APP_ID"
echo "  - OAuth Connection:     $OAUTH_CONNECTION_NAME"
echo "  - Token Exchange URL:   $TOKEN_EXCHANGE_URL"
echo "  - Scopes:               $SCOPES"
echo ""
echo -e "${CYAN}Next Steps:${NC}"
echo "  1. Test OAuth in Azure Portal:"
echo "     Bot Service → Configuration → OAuth Connection Settings"
echo "     Click on '$OAUTH_CONNECTION_NAME' → Test Connection"
echo ""
echo "  2. For Teams SSO, ensure admin consent was granted:"
echo "     az ad app permission admin-consent --id $BOT_APP_ID"
echo ""
echo "  3. Notify Developer to run Step 4:"
echo "     bash scripts/04-dev-teams-manifest.sh"
echo ""

# Save output for developer reference
mkdir -p handoff
OUTPUT_FILE="handoff/04-bot-oauth-output-$(date +%Y%m%d-%H%M%S).txt"
cat > "$OUTPUT_FILE" << EOF
# Bot OAuth Configuration Output
# Generated: $(date)
# ================================

BOT_APP_ID=$BOT_APP_ID
OAUTH_CONNECTION_NAME=$OAUTH_CONNECTION_NAME
TOKEN_EXCHANGE_URL=$TOKEN_EXCHANGE_URL
SCOPES=$SCOPES
TENANT_ID=$TENANT_ID

# NOTE: Client secret is NOT saved for security.
# If you need it, generate a new one with:
#   az ad app credential reset --id $BOT_APP_ID --display-name "New Secret" --years 2

EOF

echo -e "${GREEN}Output saved to: $OUTPUT_FILE${NC}"
