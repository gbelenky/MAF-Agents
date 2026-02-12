#!/bin/bash
# =============================================================================
# STEP 1: Entra Admin - Create App Registrations
# =============================================================================
# Role: ENTRA ADMIN
# Purpose: Create Blueprint and Agent Identity app registrations
# Run: BEFORE developer runs 'azd provision' (or 'azd up')
#
# Output: 01-admin-output-{env}.txt → share with Developer
#
# Prerequisites:
#   - Azure CLI installed
#   - Logged in with Entra Admin privileges
#   - Global Administrator or Application Administrator role
#
# Usage:
#   ./01-admin-create-apps.sh [--tenant-id <tenant-id>] [--prefix <app-prefix>]
#
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}"
echo "=============================================="
echo "  STEP 1: Entra Admin - Create App Registrations"
echo "=============================================="
echo -e "${NC}"

# Parse arguments
TENANT_ID=""
APP_PREFIX=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --tenant-id)
            TENANT_ID="$2"
            shift 2
            ;;
        --prefix)
            APP_PREFIX="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [--tenant-id <tenant-id>] [--prefix <app-prefix>]"
            echo ""
            echo "Options:"
            echo "  --tenant-id   Azure AD tenant ID (will prompt if not provided)"
            echo "  --prefix      Prefix for app registration names (default: from azd env or OneDrive-Agent)"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Auto-detect environment name from azd if no prefix specified
if [ -z "$APP_PREFIX" ]; then
    AZD_ENV=$(azd env get-value AZURE_ENV_NAME 2>/dev/null || echo "")
    if [ -n "$AZD_ENV" ]; then
        APP_PREFIX="$AZD_ENV"
        echo -e "${BLUE}Using azd environment name as app prefix: $APP_PREFIX${NC}"
    else
        APP_PREFIX="OneDrive-Agent"
        echo -e "${YELLOW}No azd environment found, using default prefix: $APP_PREFIX${NC}"
    fi
fi

# Check Azure CLI is installed
if ! command -v az &> /dev/null; then
    echo -e "${RED}Error: Azure CLI is not installed.${NC}"
    echo "Install from: https://docs.microsoft.com/cli/azure/install-azure-cli"
    exit 1
fi

# Check if logged in
CURRENT_USER=$(az ad signed-in-user show --query displayName -o tsv 2>/dev/null) || {
    echo -e "${YELLOW}Not logged in. Please log in with admin credentials.${NC}"
    if [ -n "$TENANT_ID" ]; then
        az login --tenant "$TENANT_ID"
    else
        az login
    fi
    CURRENT_USER=$(az ad signed-in-user show --query displayName -o tsv)
}

echo -e "${GREEN}✓ Logged in as: $CURRENT_USER${NC}"

# Get tenant ID if not provided
if [ -z "$TENANT_ID" ]; then
    TENANT_ID=$(az account show --query tenantId -o tsv)
    echo -e "${BLUE}Using tenant: $TENANT_ID${NC}"
fi

echo ""
echo "This script will create:"
echo "  1. Blueprint App Registration: ${APP_PREFIX}-Blueprint"
echo "  2. Agent Identity App Registration: ${APP_PREFIX}-Identity"
echo "  3. Required API permissions and scopes"
echo "  4. Client secret for local development"
echo ""
read -p "Continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

echo ""
echo -e "${BLUE}Step 1/8: Creating Blueprint App Registration...${NC}"

# Check if Blueprint already exists
EXISTING_BLUEPRINT=$(az ad app list --display-name "${APP_PREFIX}-Blueprint" --query "[0].appId" -o tsv 2>/dev/null)
if [ -n "$EXISTING_BLUEPRINT" ]; then
    echo -e "${YELLOW}Blueprint app already exists: $EXISTING_BLUEPRINT${NC}"
    read -p "Use existing app? (Y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        echo "Please delete the existing app first or use a different prefix."
        exit 1
    fi
    BLUEPRINT_ID="$EXISTING_BLUEPRINT"
else
    BLUEPRINT_ID=$(az ad app create \
        --display-name "${APP_PREFIX}-Blueprint" \
        --sign-in-audience AzureADMyOrg \
        --query appId -o tsv)
    echo -e "${GREEN}✓ Created Blueprint App: $BLUEPRINT_ID${NC}"
    
    # Create service principal
    az ad sp create --id "$BLUEPRINT_ID" > /dev/null 2>&1 || true
    echo -e "${GREEN}✓ Created Blueprint Service Principal${NC}"
fi

echo ""
echo -e "${BLUE}Step 2/8: Configuring Blueprint API...${NC}"

# Set identifier URI
az ad app update --id "$BLUEPRINT_ID" \
    --identifier-uris "api://$BLUEPRINT_ID" 2>/dev/null || true

# Generate UUID for scope (cross-platform compatible)
BLUEPRINT_SCOPE_ID=$(python3 -c "import uuid; print(uuid.uuid4())" 2>/dev/null || \
                     python -c "import uuid; print(uuid.uuid4())" 2>/dev/null || \
                     uuidgen 2>/dev/null || \
                     cat /proc/sys/kernel/random/uuid 2>/dev/null || \
                     echo "$(date +%s)-$(od -x /dev/urandom | head -1 | awk '{print $2$3$4$5}')")

# Add access_as_user scope
az rest --method PATCH \
    --uri "https://graph.microsoft.com/v1.0/applications(appId='$BLUEPRINT_ID')" \
    --headers "Content-Type=application/json" \
    --body "{
        \"api\": {
            \"oauth2PermissionScopes\": [{
                \"id\": \"$BLUEPRINT_SCOPE_ID\",
                \"adminConsentDisplayName\": \"Access as user\",
                \"adminConsentDescription\": \"Allow the agent to access resources on behalf of the signed-in user\",
                \"userConsentDisplayName\": \"Access as you\",
                \"userConsentDescription\": \"Allow the agent to access resources on your behalf\",
                \"isEnabled\": true,
                \"type\": \"User\",
                \"value\": \"access_as_user\"
            }]
        }
    }" > /dev/null

echo -e "${GREEN}✓ Added access_as_user scope to Blueprint${NC}"

echo ""
echo -e "${BLUE}Step 3/8: Creating Agent Identity App Registration...${NC}"

# Check if Agent Identity already exists
EXISTING_AGENT=$(az ad app list --display-name "${APP_PREFIX}-Identity" --query "[0].appId" -o tsv 2>/dev/null)
if [ -n "$EXISTING_AGENT" ]; then
    echo -e "${YELLOW}Agent Identity app already exists: $EXISTING_AGENT${NC}"
    read -p "Use existing app? (Y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        echo "Please delete the existing app first or use a different prefix."
        exit 1
    fi
    AGENT_ID="$EXISTING_AGENT"
else
    AGENT_ID=$(az ad app create \
        --display-name "${APP_PREFIX}-Identity" \
        --sign-in-audience AzureADMyOrg \
        --query appId -o tsv)
    echo -e "${GREEN}✓ Created Agent Identity App: $AGENT_ID${NC}"
    
    # Create service principal
    az ad sp create --id "$AGENT_ID" > /dev/null 2>&1 || true
    echo -e "${GREEN}✓ Created Agent Identity Service Principal${NC}"
fi

echo ""
echo -e "${BLUE}Step 4/8: Configuring Agent Identity API...${NC}"

# Set identifier URI and enable public client
az ad app update --id "$AGENT_ID" \
    --identifier-uris "api://$AGENT_ID" \
    --is-fallback-public-client true 2>/dev/null || true

# Generate UUID for agent scope
AGENT_SCOPE_ID=$(python3 -c "import uuid; print(uuid.uuid4())" 2>/dev/null || \
                 python -c "import uuid; print(uuid.uuid4())" 2>/dev/null || \
                 uuidgen 2>/dev/null || \
                 cat /proc/sys/kernel/random/uuid 2>/dev/null || \
                 echo "$(date +%s)-$(od -x /dev/urandom | head -1 | awk '{print $2$3$4$5}')")

# First, add access_as_user scope
az rest --method PATCH \
    --uri "https://graph.microsoft.com/v1.0/applications(appId='$AGENT_ID')" \
    --headers "Content-Type=application/json" \
    --body "{
        \"api\": {
            \"oauth2PermissionScopes\": [{
                \"id\": \"$AGENT_SCOPE_ID\",
                \"adminConsentDisplayName\": \"Access as user\",
                \"adminConsentDescription\": \"Allow access on behalf of the signed-in user\",
                \"userConsentDisplayName\": \"Access as you\",
                \"userConsentDescription\": \"Allow access on your behalf\",
                \"isEnabled\": true,
                \"type\": \"User\",
                \"value\": \"access_as_user\"
            }]
        }
    }" > /dev/null

echo -e "${GREEN}✓ Added access_as_user scope to Agent Identity${NC}"

# Then, pre-authorize clients for SSO and set token version
# Teams clients:
#   Teams Desktop/Mobile: 1fec8e78-bce4-4aaf-ab1b-5451cc387264
#   Teams Web: 5e3ce6c0-2b1f-4285-8d4b-75ee78787346
#   Teams (General): d3590ed6-52b3-4102-aeff-aad2292ab01c
#   Teams Mobile/Desktop (Alt): 27922004-5251-4030-b22d-91ecd9a37ea4
#   Teams Web (Alt): bc59ab01-8403-45c6-8796-ac3ef710b3e3
#   Teams Admin: 0ec893e0-5785-4de6-99da-4ed124e5296c
#   Office: 4765445b-32c6-49b0-83e6-1d93765276ca
# Development/Testing:
#   Agents Playground (https://playground.dev.agents.azure.com): ab3be6b7-f5df-413d-ac2d-abf1e3fd9c0b
#   Note: Agents Playground is a Microsoft first-party app for testing M365 Agents SDK bots.
#         Pre-authorizing it allows seamless SSO testing without consent prompts.
az rest --method PATCH \
    --uri "https://graph.microsoft.com/v1.0/applications(appId='$AGENT_ID')" \
    --headers "Content-Type=application/json" \
    --body "{
        \"api\": {
            \"requestedAccessTokenVersion\": 2,
            \"preAuthorizedApplications\": [
                {\"appId\": \"1fec8e78-bce4-4aaf-ab1b-5451cc387264\", \"delegatedPermissionIds\": [\"$AGENT_SCOPE_ID\"]},
                {\"appId\": \"5e3ce6c0-2b1f-4285-8d4b-75ee78787346\", \"delegatedPermissionIds\": [\"$AGENT_SCOPE_ID\"]},
                {\"appId\": \"d3590ed6-52b3-4102-aeff-aad2292ab01c\", \"delegatedPermissionIds\": [\"$AGENT_SCOPE_ID\"]},
                {\"appId\": \"27922004-5251-4030-b22d-91ecd9a37ea4\", \"delegatedPermissionIds\": [\"$AGENT_SCOPE_ID\"]},
                {\"appId\": \"bc59ab01-8403-45c6-8796-ac3ef710b3e3\", \"delegatedPermissionIds\": [\"$AGENT_SCOPE_ID\"]},
                {\"appId\": \"0ec893e0-5785-4de6-99da-4ed124e5296c\", \"delegatedPermissionIds\": [\"$AGENT_SCOPE_ID\"]},
                {\"appId\": \"4765445b-32c6-49b0-83e6-1d93765276ca\", \"delegatedPermissionIds\": [\"$AGENT_SCOPE_ID\"]},
                {\"appId\": \"ab3be6b7-f5df-413d-ac2d-abf1e3fd9c0b\", \"delegatedPermissionIds\": [\"$AGENT_SCOPE_ID\"]}
            ]
        }
    }" > /dev/null

echo -e "${GREEN}✓ Pre-authorized clients for SSO (Teams + Agents Playground)${NC}"

echo ""
echo -e "${BLUE}Step 5/8: Adding Microsoft Graph Permissions...${NC}"

# Add all required Graph delegated permissions for SSO and Graph API access
# Files.Read = 10465720-29dd-4523-a11a-6a75c743c9d9
# Files.ReadWrite = 5c28f0bf-8a70-41f1-8ab2-9032436ddb65
# User.Read = e1fe6dd8-ba31-4d61-89e7-88639da4683d
# openid = 37f7f235-527c-4136-accd-4a02d197296e
# profile = 14dad69e-099b-42c9-810b-d002981feec1
az rest --method PATCH \
    --uri "https://graph.microsoft.com/v1.0/applications(appId='$AGENT_ID')" \
    --headers "Content-Type=application/json" \
    --body "{
        \"requiredResourceAccess\": [{
            \"resourceAppId\": \"00000003-0000-0000-c000-000000000000\",
            \"resourceAccess\": [
                {\"id\": \"10465720-29dd-4523-a11a-6a75c743c9d9\", \"type\": \"Scope\"},
                {\"id\": \"5c28f0bf-8a70-41f1-8ab2-9032436ddb65\", \"type\": \"Scope\"},
                {\"id\": \"e1fe6dd8-ba31-4d61-89e7-88639da4683d\", \"type\": \"Scope\"},
                {\"id\": \"37f7f235-527c-4136-accd-4a02d197296e\", \"type\": \"Scope\"},
                {\"id\": \"14dad69e-099b-42c9-810b-d002981feec1\", \"type\": \"Scope\"}
            ]
        }]
    }" > /dev/null

echo -e "${GREEN}✓ Added Graph permissions: Files.Read, Files.ReadWrite, User.Read, openid, profile${NC}"

echo ""
echo -e "${BLUE}Step 6/8: Granting Admin Consent...${NC}"

# Wait for permissions to propagate
sleep 5

# Grant admin consent
if az ad app permission admin-consent --id "$AGENT_ID" 2>/dev/null; then
    echo -e "${GREEN}✓ Admin consent granted${NC}"
else
    echo -e "${YELLOW}⚠ Auto-consent failed. Trying again after delay...${NC}"
    sleep 5
    if az ad app permission admin-consent --id "$AGENT_ID" 2>/dev/null; then
        echo -e "${GREEN}✓ Admin consent granted (on retry)${NC}"
    else
        echo -e "${RED}⚠ Could not auto-grant consent. Please grant manually:${NC}"
        echo "   https://login.microsoftonline.com/$TENANT_ID/adminconsent?client_id=$AGENT_ID"
        echo ""
        echo "   Or run: az ad app permission admin-consent --id $AGENT_ID"
        read -p "Press Enter after granting consent..." 
    fi
fi

echo ""
echo -e "${BLUE}Step 7/8: Creating Client Secret (for local development)...${NC}"

SECRET=$(az ad app credential reset --id "$AGENT_ID" \
    --display-name "LocalDev-Secret-$(date +%Y%m%d)" \
    --years 1 \
    --query password -o tsv 2>/dev/null) || {
    echo -e "${YELLOW}⚠ Could not create secret. Create manually in Azure Portal.${NC}"
    SECRET="<create-manually-in-portal>"
}

if [ "$SECRET" != "<create-manually-in-portal>" ]; then
    echo -e "${GREEN}✓ Client secret created (valid for 1 year)${NC}"
fi

echo ""
echo -e "${BLUE}Step 8/8: Adding Bot Framework redirect URI (for Teams SSO)...${NC}"

az ad app update --id "$AGENT_ID" \
    --web-redirect-uris "https://token.botframework.com/.auth/web/redirect" 2>/dev/null || true

echo -e "${GREEN}✓ Bot Framework redirect URI added${NC}"

# Output summary
echo ""
echo -e "${GREEN}"
echo "=============================================="
echo "  ✅ PHASE 1 COMPLETE"
echo "=============================================="
echo -e "${NC}"
echo ""
echo "App Registrations Created:"
echo "  Blueprint:       ${APP_PREFIX}-Blueprint"
echo "  Agent Identity:  ${APP_PREFIX}-Identity"
echo ""

# Automatically save to azd environment if available
if command -v azd &> /dev/null; then
    echo -e "${BLUE}Saving values to azd environment...${NC}"
    azd env set TENANT_ID "$TENANT_ID" 2>/dev/null || true
    azd env set BLUEPRINT_CLIENT_ID "$BLUEPRINT_ID" 2>/dev/null || true
    azd env set AGENT_IDENTITY_CLIENT_ID "$AGENT_ID" 2>/dev/null || true
    azd env set BOT_MICROSOFT_APP_ID "$AGENT_ID" 2>/dev/null || true
    azd env set ENABLE_BOT "true" 2>/dev/null || true
    echo -e "${GREEN}✓ Values saved to azd environment${NC}"
    echo ""
fi

echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}  VALUES FOR REFERENCE:${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "TENANT_ID=$TENANT_ID"
echo "BLUEPRINT_CLIENT_ID=$BLUEPRINT_ID"
echo "AGENT_IDENTITY_CLIENT_ID=$AGENT_ID"
echo "AGENT_IDENTITY_CLIENT_SECRET=$SECRET"
echo ""
echo "# For Bot Service / Teams / M365 Copilot:"
echo "BOT_MICROSOFT_APP_ID=$AGENT_ID"
echo "SSO_TOKEN_EXCHANGE_URL=api://botid-$AGENT_ID"
echo ""
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "NEXT STEPS:"
echo "  1. Run: azd provision (or azd up for full deploy)"
echo "  2. Then run: bash scripts/03-admin-create-fic.sh"
echo "     (It will auto-detect the Managed Identity Client ID)"
echo ""

# Save to file for reference (in handoff folder)
mkdir -p handoff
OUTPUT_FILE="handoff/01-admin-output-${APP_PREFIX}-$(date +%Y%m%d-%H%M%S).txt"
cat > "$OUTPUT_FILE" << EOF
# Step 1: Admin Output - $(date)
# Environment: ${APP_PREFIX}
# Share this file securely with the Developer

TENANT_ID=$TENANT_ID
BLUEPRINT_CLIENT_ID=$BLUEPRINT_ID
AGENT_IDENTITY_CLIENT_ID=$AGENT_ID
AGENT_IDENTITY_CLIENT_SECRET=$SECRET

# For Bot Service / Teams / M365 Copilot
BOT_MICROSOFT_APP_ID=$AGENT_ID
SSO_TOKEN_EXCHANGE_URL=api://botid-$AGENT_ID

# App Names
BLUEPRINT_APP_NAME=${APP_PREFIX}-Blueprint
AGENT_IDENTITY_APP_NAME=${APP_PREFIX}-Identity
EOF

echo -e "${GREEN}Values saved to: $OUTPUT_FILE${NC}"
echo ""
