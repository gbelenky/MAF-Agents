#!/bin/bash
# =============================================================================
# STEP 1: Entra Admin - Create App Registration
# =============================================================================
# Role: ENTRA ADMIN
# Purpose: Create Agent Identity app registration for OBO authentication
# Run: BEFORE developer runs 'azd provision' (or 'azd up')
#
# Output: handoff/01-admin-output-{env}.txt → share with Developer
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
echo "  STEP 1: Entra Admin - Create App Registration"
echo "  (Fabric Data Agent Teams Bot)"
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
            echo "  --prefix      Prefix for app registration names (default: from azd env or prompt)"
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
    echo ""
    echo -e "${YELLOW}No --prefix specified.${NC}"
    echo "The prefix is used for the app registration name (e.g., 'fabricagent' creates 'fabricagent-Agent')."
    echo "This should match the azd environment name the developer will use."
    echo ""
    read -p "Enter app name prefix (e.g., fabricagent, myagent): " APP_PREFIX
    
    if [ -z "$APP_PREFIX" ]; then
        echo -e "${RED}Error: Prefix is required.${NC}"
        exit 1
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

APP_NAME="${APP_PREFIX}-Agent"

echo ""
echo "This script will create:"
echo "  1. App Registration: ${APP_NAME}"
echo "  2. access_as_user scope for Teams SSO"
echo "  3. Microsoft Fabric API permissions"
echo "  4. Pre-authorized Teams clients"
echo "  5. Admin consent"
echo "  6. Client secret for local development"
echo ""
read -p "Continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

echo ""
echo -e "${BLUE}Step 1/6: Creating App Registration...${NC}"

# Check if app already exists
EXISTING_APP=$(az ad app list --display-name "${APP_NAME}" --query "[0].appId" -o tsv 2>/dev/null)
if [ -n "$EXISTING_APP" ]; then
    echo -e "${YELLOW}App already exists: $EXISTING_APP${NC}"
    read -p "Use existing app? (Y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        echo "Please delete the existing app first or use a different prefix."
        exit 1
    fi
    APP_ID="$EXISTING_APP"
else
    APP_ID=$(az ad app create \
        --display-name "${APP_NAME}" \
        --sign-in-audience AzureADMyOrg \
        --query appId -o tsv)
    echo -e "${GREEN}✓ Created App: $APP_ID${NC}"
    
    # Create service principal
    az ad sp create --id "$APP_ID" > /dev/null 2>&1 || true
    echo -e "${GREEN}✓ Created Service Principal${NC}"
fi

echo ""
echo -e "${BLUE}Step 2/6: Configuring API (access_as_user scope + SSO)...${NC}"

# Set identifier URI (with botid- prefix for Teams SSO) and enable public client
az ad app update --id "$APP_ID" \
    --identifier-uris "api://botid-$APP_ID" \
    --is-fallback-public-client true 2>/dev/null || true

# Generate UUID for scope (Windows compatible - tries python first)
SCOPE_ID=$(python3 -c "import uuid; print(uuid.uuid4())" 2>/dev/null || \
           python -c "import uuid; print(uuid.uuid4())" 2>/dev/null || \
           uuidgen 2>/dev/null || \
           cat /proc/sys/kernel/random/uuid 2>/dev/null || \
           echo "$(date +%s)-$(od -x /dev/urandom | head -1 | awk '{print $2$3$4$5}')")

# Add access_as_user scope using az rest (more reliable than az ad app update)
az rest --method PATCH \
    --uri "https://graph.microsoft.com/v1.0/applications(appId='$APP_ID')" \
    --headers "Content-Type=application/json" \
    --body "{
        \"api\": {
            \"oauth2PermissionScopes\": [{
                \"id\": \"$SCOPE_ID\",
                \"adminConsentDisplayName\": \"Access as user\",
                \"adminConsentDescription\": \"Allow the application to access Fabric Data Agent on behalf of the signed-in user\",
                \"userConsentDisplayName\": \"Access as you\",
                \"userConsentDescription\": \"Allow the application to access Fabric Data Agent on your behalf\",
                \"isEnabled\": true,
                \"type\": \"User\",
                \"value\": \"access_as_user\"
            }]
        }
    }" > /dev/null

echo -e "${GREEN}✓ Added access_as_user scope${NC}"

# Pre-authorize Teams clients for SSO and set token version
# Teams clients:
#   Teams Desktop/Mobile: 1fec8e78-bce4-4aaf-ab1b-5451cc387264
#   Teams Web: 5e3ce6c0-2b1f-4285-8d4b-75ee78787346
#   Teams (General): d3590ed6-52b3-4102-aeff-aad2292ab01c
#   Teams Mobile/Desktop (Alt): 27922004-5251-4030-b22d-91ecd9a37ea4
#   Teams Web (Alt): bc59ab01-8403-45c6-8796-ac3ef710b3e3
#   Teams Admin: 0ec893e0-5785-4de6-99da-4ed124e5296c
#   Office: 4765445b-32c6-49b0-83e6-1d93765276ca
# Development/Testing:
#   Agents Playground: ab3be6b7-f5df-413d-ac2d-abf1e3fd9c0b
az rest --method PATCH \
    --uri "https://graph.microsoft.com/v1.0/applications(appId='$APP_ID')" \
    --headers "Content-Type=application/json" \
    --body "{
        \"api\": {
            \"requestedAccessTokenVersion\": 2,
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
    }" > /dev/null

echo -e "${GREEN}✓ Pre-authorized Teams + Agents Playground clients${NC}"

echo ""
echo -e "${BLUE}Step 3/6: Adding API Permissions...${NC}"

# Add Fabric API permissions and Graph permissions using az rest
# Microsoft Fabric API: 00000009-0000-0000-c000-000000000000
#   Workspace.ReadWrite.All (delegated): b2a1ad0e-c0a5-4b8b-8b19-6c77e85ae5e4
# Microsoft Graph: 00000003-0000-0000-c000-000000000000
#   User.Read: e1fe6dd8-ba31-4d61-89e7-88639da4683d
#   openid: 37f7f235-527c-4136-accd-4a02d197296e
#   profile: 14dad69e-099b-42c9-810b-d002981feec1
az rest --method PATCH \
    --uri "https://graph.microsoft.com/v1.0/applications(appId='$APP_ID')" \
    --headers "Content-Type=application/json" \
    --body "{
        \"requiredResourceAccess\": [
            {
                \"resourceAppId\": \"00000009-0000-0000-c000-000000000000\",
                \"resourceAccess\": [
                    {\"id\": \"b2a1ad0e-c0a5-4b8b-8b19-6c77e85ae5e4\", \"type\": \"Scope\"}
                ]
            },
            {
                \"resourceAppId\": \"00000003-0000-0000-c000-000000000000\",
                \"resourceAccess\": [
                    {\"id\": \"e1fe6dd8-ba31-4d61-89e7-88639da4683d\", \"type\": \"Scope\"},
                    {\"id\": \"37f7f235-527c-4136-accd-4a02d197296e\", \"type\": \"Scope\"},
                    {\"id\": \"14dad69e-099b-42c9-810b-d002981feec1\", \"type\": \"Scope\"}
                ]
            }
        ]
    }" > /dev/null

echo -e "${GREEN}✓ Added permissions: Fabric Workspace.ReadWrite.All, User.Read, openid, profile${NC}"

echo ""
echo -e "${BLUE}Step 4/6: Granting Admin Consent...${NC}"

# Wait for permissions to propagate (Entra can take 10-30 seconds)
echo "Waiting for permissions to propagate..."
sleep 10

# Grant admin consent with multiple retries
CONSENT_GRANTED=false
for attempt in 1 2 3; do
    echo "Attempt $attempt/3..."
    if az ad app permission admin-consent --id "$APP_ID" 2>&1; then
        echo -e "${GREEN}✓ Admin consent granted${NC}"
        CONSENT_GRANTED=true
        break
    else
        echo -e "${YELLOW}⚠ Attempt $attempt failed. Waiting 10 seconds...${NC}"
        sleep 10
    fi
done

if [ "$CONSENT_GRANTED" = false ]; then
    echo -e "${RED}⚠ Auto-consent failed after 3 attempts.${NC}"
    echo ""
    echo "Please grant consent manually:"
    echo "  1. Open: https://login.microsoftonline.com/$TENANT_ID/adminconsent?client_id=$APP_ID"
    echo "  2. Log in as admin and click 'Accept'"
    echo ""
    read -p "Press Enter after granting consent..."
    
    # Verify consent was granted
    if az ad app permission admin-consent --id "$APP_ID" 2>&1; then
        echo -e "${GREEN}✓ Consent verified${NC}"
    else
        echo -e "${YELLOW}⚠ Consent verification failed. Continuing - you may need to grant consent later.${NC}"
    fi
fi

echo ""
echo -e "${BLUE}Step 5/6: Creating Client Secret (for local development)...${NC}"

SECRET=$(az ad app credential reset --id "$APP_ID" \
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
echo -e "${BLUE}Step 6/6: Adding Bot Framework redirect URI...${NC}"

az ad app update --id "$APP_ID" \
    --web-redirect-uris "https://token.botframework.com/.auth/web/redirect" 2>/dev/null || true

echo -e "${GREEN}✓ Bot Framework redirect URI added${NC}"

# Output summary
echo ""
echo -e "${GREEN}"
echo "=============================================="
echo "  ✅ STEP 1 COMPLETE"
echo "=============================================="
echo -e "${NC}"
echo ""
echo "App Registration Created: ${APP_NAME}"
echo ""

echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}  VALUES FOR DEVELOPER:${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "TENANT_ID=$TENANT_ID"
echo "BOT_CLIENT_ID=$APP_ID"
echo "BOT_CLIENT_SECRET=$SECRET"
echo ""
echo "# For Teams SSO:"
echo "SSO_TOKEN_EXCHANGE_URL=api://botid-$APP_ID"
echo ""
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "NEXT STEPS:"
echo "  1. Share values above with Developer"
echo "  2. Developer runs: azd up"
echo "  3. Then run: bash scripts/03-admin-bot-oauth.sh"
echo ""

# Save to handoff file
mkdir -p handoff
OUTPUT_FILE="handoff/01-admin-output-${APP_PREFIX}-$(date +%Y%m%d-%H%M%S).txt"
cat > "$OUTPUT_FILE" << EOF
# Step 1: Admin Output - $(date)
# Environment: ${APP_PREFIX}
# Share this file securely with the Developer

TENANT_ID=$TENANT_ID
BOT_CLIENT_ID=$APP_ID
BOT_CLIENT_SECRET=$SECRET

# For Teams SSO
SSO_TOKEN_EXCHANGE_URL=api://botid-$APP_ID

# App Name
APP_NAME=${APP_NAME}
EOF

echo -e "${GREEN}Values saved to: $OUTPUT_FILE${NC}"
echo ""
