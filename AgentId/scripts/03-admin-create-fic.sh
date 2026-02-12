#!/bin/bash
# =============================================================================
# STEP 3: Entra Admin - Create Federated Identity Credential
# =============================================================================
# Role: ENTRA ADMIN
# Purpose: Link Managed Identity to Agent Identity app for Bot auth
# Run: AFTER developer runs 'azd up' and shares 02-dev-handoff-{env}.txt
#
# Input: 02-dev-handoff-{env}.txt (auto-detected) OR command-line args
#
# Prerequisites:
#   - Azure CLI installed
#   - Logged in with Entra Admin privileges
#   - Step 1 completed (Agent Identity app exists)
#   - Developer completed azd up (Managed Identity created)
#
# Usage:
#   ./03-admin-create-fic.sh [options]
#
# Options:
#   --tenant-id <id>          Azure AD tenant ID
#   --agent-identity-id <id>  Agent Identity App Client ID (from Step 1)
#   --mi-client-id <id>       Managed Identity Client ID (from developer)
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
echo "  Phase 3: Entra Admin - Create FIC"
echo "=============================================="
echo -e "${NC}"

# Parse arguments
TENANT_ID=""
AGENT_IDENTITY_ID=""
MI_CLIENT_ID=""
FIC_NAME="OneDriveAgentManagedIdentity"

while [[ $# -gt 0 ]]; do
    case $1 in
        --tenant-id)
            TENANT_ID="$2"
            shift 2
            ;;
        --agent-identity-id)
            AGENT_IDENTITY_ID="$2"
            shift 2
            ;;
        --mi-client-id)
            MI_CLIENT_ID="$2"
            shift 2
            ;;
        --fic-name)
            FIC_NAME="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --tenant-id <id>           Azure AD tenant ID"
            echo "  --agent-identity-id <id>   Agent Identity App Client ID (from Phase 1)"
            echo "  --mi-client-id <id>        Managed Identity Client ID (from Developer)"
            echo "  --fic-name <name>          FIC name (default: OneDriveAgentManagedIdentity)"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Try to load from dev handoff file if available (for separate admin/dev workflow)
ADMIN_INPUT_FILE=""
# Check handoff folder first, then current directory
for f in handoff/02-dev-handoff-*.txt 02-dev-handoff-*.txt; do
    if [ -f "$f" ]; then
        ADMIN_INPUT_FILE="$f"
        break
    fi
done

if [ -n "$ADMIN_INPUT_FILE" ] && [ -z "$AGENT_IDENTITY_ID" ] && [ -z "$MI_CLIENT_ID" ]; then
    echo -e "${GREEN}✓ Found admin input file: $ADMIN_INPUT_FILE${NC}"
    echo -e "${YELLOW}  Loading values from file...${NC}"
    
    # Source the file to get variables
    if [ -z "$AGENT_IDENTITY_ID" ]; then
        FILE_AGENT_ID=$(grep "^AGENT_IDENTITY_CLIENT_ID=" "$ADMIN_INPUT_FILE" | cut -d'=' -f2)
        if [ -n "$FILE_AGENT_ID" ]; then
            AGENT_IDENTITY_ID="$FILE_AGENT_ID"
            echo -e "${GREEN}  ✓ AGENT_IDENTITY_CLIENT_ID from file${NC}"
        fi
    fi
    
    if [ -z "$MI_CLIENT_ID" ]; then
        FILE_MI_ID=$(grep "^MANAGED_IDENTITY_CLIENT_ID=" "$ADMIN_INPUT_FILE" | cut -d'=' -f2)
        if [ -n "$FILE_MI_ID" ]; then
            MI_CLIENT_ID="$FILE_MI_ID"
            echo -e "${GREEN}  ✓ MANAGED_IDENTITY_CLIENT_ID from file${NC}"
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

# Auto-detect Agent Identity ID from azd environment if not provided
if [ -z "$AGENT_IDENTITY_ID" ]; then
    AZD_AGENT_ID=$(azd env get-value AGENT_IDENTITY_CLIENT_ID 2>/dev/null || echo "")
    if [ -z "$AZD_AGENT_ID" ]; then
        AZD_AGENT_ID=$(azd env get-value BOT_MICROSOFT_APP_ID 2>/dev/null || echo "")
    fi
    if [ -n "$AZD_AGENT_ID" ]; then
        echo -e "${GREEN}✓ Auto-detected from azd: AGENT_IDENTITY_CLIENT_ID=$AZD_AGENT_ID${NC}"
        AGENT_IDENTITY_ID="$AZD_AGENT_ID"
    else
        echo ""
        echo "Enter the Agent Identity App Client ID from Phase 1:"
        echo "(This is the same as BOT_MICROSOFT_APP_ID)"
        read -p "AGENT_IDENTITY_CLIENT_ID: " AGENT_IDENTITY_ID
    fi
fi

if [ -z "$AGENT_IDENTITY_ID" ]; then
    echo -e "${RED}Error: Agent Identity Client ID is required${NC}"
    exit 1
fi

# Verify Agent Identity app exists
AGENT_IDENTITY_NAME=$(az ad app show --id "$AGENT_IDENTITY_ID" --query displayName -o tsv 2>/dev/null) || {
    echo -e "${RED}Error: Agent Identity app not found: $AGENT_IDENTITY_ID${NC}"
    echo "Make sure Phase 1 was completed successfully."
    exit 1
}
echo -e "${GREEN}✓ Found Agent Identity app: $AGENT_IDENTITY_NAME${NC}"

# Auto-detect MI Client ID from azd environment if not provided
if [ -z "$MI_CLIENT_ID" ]; then
    AZD_MI_ID=$(azd env get-value MANAGED_IDENTITY_CLIENT_ID 2>/dev/null || echo "")
    if [ -n "$AZD_MI_ID" ]; then
        echo -e "${GREEN}✓ Auto-detected from azd: MANAGED_IDENTITY_CLIENT_ID=$AZD_MI_ID${NC}"
        MI_CLIENT_ID="$AZD_MI_ID"
    else
        echo ""
        echo "Enter the Managed Identity Client ID from the Developer:"
        echo "(Developer can get this with: azd env get-value MANAGED_IDENTITY_CLIENT_ID)"
        read -p "MANAGED_IDENTITY_CLIENT_ID: " MI_CLIENT_ID
    fi
fi

if [ -z "$MI_CLIENT_ID" ]; then
    echo -e "${RED}Error: Managed Identity Client ID is required${NC}"
    exit 1
fi

# Validate MI Client ID format (should be a GUID)
if [[ ! "$MI_CLIENT_ID" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
    echo -e "${YELLOW}Warning: MI Client ID doesn't look like a valid GUID${NC}"
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Look up the Principal ID (Object ID) from the Client ID
# The FIC subject MUST be the principal ID, not the client ID
echo -e "${BLUE}Looking up Managed Identity Principal ID...${NC}"
MI_PRINCIPAL_ID=$(az ad sp show --id "$MI_CLIENT_ID" --query "id" -o tsv 2>/dev/null) || {
    echo -e "${RED}Error: Could not find service principal for client ID: $MI_CLIENT_ID${NC}"
    echo "Make sure the Managed Identity exists and you have permission to read it."
    exit 1
}
echo -e "${GREEN}✓ Found Principal ID: $MI_PRINCIPAL_ID${NC}"

echo ""
echo "Creating Federated Identity Credential:"
echo "  Agent Identity App: $AGENT_IDENTITY_NAME ($AGENT_IDENTITY_ID)"
echo "  MI Client ID:       $MI_CLIENT_ID"
echo "  MI Principal ID:    $MI_PRINCIPAL_ID (used for FIC subject)"
echo "  FIC Name:           $FIC_NAME"
echo "  Issuer:             https://login.microsoftonline.com/$TENANT_ID/v2.0"
echo "  Audience:           api://AzureADTokenExchange"
echo ""
read -p "Continue? (Y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Nn]$ ]]; then
    echo "Aborted."
    exit 0
fi

echo ""
echo -e "${BLUE}Checking for existing FIC...${NC}"

# Check if FIC already exists
EXISTING_FIC=$(az rest --method GET \
    --uri "https://graph.microsoft.com/v1.0/applications(appId='$AGENT_IDENTITY_ID')/federatedIdentityCredentials" \
    --query "value[?name=='$FIC_NAME'].id" -o tsv 2>/dev/null) || true

if [ -n "$EXISTING_FIC" ]; then
    echo -e "${YELLOW}FIC already exists with name: $FIC_NAME${NC}"
    read -p "Delete and recreate? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Deleting existing FIC..."
        az rest --method DELETE \
            --uri "https://graph.microsoft.com/v1.0/applications(appId='$AGENT_IDENTITY_ID')/federatedIdentityCredentials/$EXISTING_FIC" \
            > /dev/null
        echo -e "${GREEN}✓ Deleted existing FIC${NC}"
    else
        echo "Keeping existing FIC. Exiting."
        exit 0
    fi
fi

echo ""
echo -e "${BLUE}Creating Federated Identity Credential...${NC}"

# Create the FIC on Agent Identity app (required for Bot Framework auth)
# IMPORTANT: The subject MUST be the Principal ID (Object ID), NOT the Client ID
az rest --method POST \
    --uri "https://graph.microsoft.com/v1.0/applications(appId='$AGENT_IDENTITY_ID')/federatedIdentityCredentials" \
    --headers "Content-Type=application/json" \
    --body "{
        \"name\": \"$FIC_NAME\",
        \"issuer\": \"https://login.microsoftonline.com/$TENANT_ID/v2.0\",
        \"subject\": \"$MI_PRINCIPAL_ID\",
        \"audiences\": [\"api://AzureADTokenExchange\"],
        \"description\": \"FIC for Bot to authenticate via Managed Identity (using principal ID)\"
    }" > /dev/null

echo -e "${GREEN}✓ Federated Identity Credential created${NC}"

# Verify the FIC was created
echo ""
echo -e "${BLUE}Verifying FIC...${NC}"

FIC_INFO=$(az rest --method GET \
    --uri "https://graph.microsoft.com/v1.0/applications(appId='$AGENT_IDENTITY_ID')/federatedIdentityCredentials" \
    --query "value[?name=='$FIC_NAME'].{name:name, subject:subject, issuer:issuer}" -o table 2>/dev/null) || true

if [ -n "$FIC_INFO" ]; then
    echo "$FIC_INFO"
    echo ""
    echo -e "${GREEN}✓ FIC verified successfully${NC}"
else
    echo -e "${YELLOW}⚠ Could not verify FIC. Please check in Azure Portal.${NC}"
fi

# Output summary
echo ""
echo -e "${GREEN}"
echo "=============================================="
echo "  ✅ PHASE 3 COMPLETE"
echo "=============================================="
echo -e "${NC}"
echo ""
echo "The Federated Identity Credential has been created."
echo "The Managed Identity can now authenticate as the Agent Identity app for Bot Service."
echo ""
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}  CONFIRM TO DEVELOPER:${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "✅ Federated Identity Credential created successfully."
echo "   The agent is ready for testing."
echo ""
echo "Developer can now run Phase 4 tests:"
echo "  1. Test health endpoint: curl \$APP_URL/health"
echo "  2. Get user token: az account get-access-token --resource api://\$AGENT_ID"
echo "  3. Test agent: curl -X POST \$APP_URL/api/chat ..."
echo ""
