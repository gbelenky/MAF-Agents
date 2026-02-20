#!/bin/bash
# =============================================================================
# STEP 2: Developer - Generate Handoff File for Admin
# =============================================================================
# Role: DEVELOPER
# Purpose: Generate file with azd deployment values for Entra Admin
# Run: AFTER 'azd provision' (or 'azd up') completes
#
# Output: 02-dev-handoff-{env}.txt → share with Entra Admin
#
# Usage:
#   ./02-dev-generate-handoff.sh
#
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}"
echo "=============================================="
echo "  STEP 2: Developer - Generate Admin Handoff"
echo "  (Fabric Data Agent Teams Bot)"
echo "=============================================="
echo -e "${NC}"

# Check azd is available
if ! command -v azd &> /dev/null; then
    echo -e "${RED}Error: Azure Developer CLI (azd) is not installed.${NC}"
    exit 1
fi

# Get environment name
ENV_NAME=$(azd env get-value AZURE_ENV_NAME 2>/dev/null) || {
    echo -e "${RED}Error: No azd environment found. Run 'azd env new' first.${NC}"
    exit 1
}

echo -e "${GREEN}✓ Using azd environment: $ENV_NAME${NC}"

# Get required values
BOT_CLIENT_ID=$(azd env get-value BOT_CLIENT_ID 2>/dev/null) || {
    echo -e "${RED}Error: BOT_CLIENT_ID not found. Was Step 1 run?${NC}"
    exit 1
}

# Construct resource names (following azd conventions)
RESOURCE_GROUP="rg-$ENV_NAME"
BOT_NAME="bot-$ENV_NAME"
APP_SERVICE_NAME="app-$ENV_NAME"
APP_URL="https://$APP_SERVICE_NAME.azurewebsites.net"

# Get tenant ID (try azd first, fall back to az account)
TENANT_ID=$(azd env get-value TENANT_ID 2>&1 | grep -v "^ERROR\|not found" | head -1)
if [ -z "$TENANT_ID" ]; then
    TENANT_ID=$(az account show --query tenantId -o tsv)
fi

# Generate output file (in handoff folder)
mkdir -p handoff
OUTPUT_FILE="handoff/02-dev-handoff-$ENV_NAME.txt"
cat > "$OUTPUT_FILE" << EOF
# =============================================================================
# Step 2: Developer Handoff for Entra Admin
# =============================================================================
# Environment: $ENV_NAME
# Generated: $(date)
# 
# Share this file securely with the Entra Admin.
# The Admin needs these values for Step 3 (Bot OAuth).
#
# =============================================================================

# Environment Info
AZURE_ENV_NAME=$ENV_NAME

# Tenant
TENANT_ID=$TENANT_ID

# Bot Identity (from Step 1 - needed for OAuth)
BOT_CLIENT_ID=$BOT_CLIENT_ID

# Azure Resources (from azd provision - needed for Bot OAuth)
RESOURCE_GROUP=$RESOURCE_GROUP
BOT_NAME=$BOT_NAME
APP_SERVICE_NAME=$APP_SERVICE_NAME
APP_URL=$APP_URL

# =============================================================================
# ADMIN COMMAND (Step 3)
# =============================================================================
# 
# Configure Bot OAuth (creates secret + OAuth connection + sets App Service config):
#   bash scripts/03-admin-bot-oauth.sh \\
#     --bot-app-id $BOT_CLIENT_ID \\
#     --resource-group $RESOURCE_GROUP \\
#     --bot-name $BOT_NAME
#
# Or use handoff file:
#   bash scripts/03-admin-bot-oauth.sh --handoff-file handoff/02-dev-handoff-$ENV_NAME.txt
#
# =============================================================================
EOF

echo ""
echo -e "${GREEN}✓ Generated: $OUTPUT_FILE${NC}"
echo ""
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}  SHARE THIS FILE WITH THE ENTRA ADMIN${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
cat "$OUTPUT_FILE"
echo ""
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Next Steps:"
echo "  1. Send '$OUTPUT_FILE' to the Entra Admin (securely!)"
echo "  2. Admin runs Step 3 (03-admin-bot-oauth.sh)"
echo "  3. Then run: bash scripts/04-dev-teams-manifest.sh"
echo ""
