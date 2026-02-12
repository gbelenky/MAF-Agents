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
MANAGED_IDENTITY_CLIENT_ID=$(azd env get-value MANAGED_IDENTITY_CLIENT_ID 2>/dev/null) || {
    echo -e "${RED}Error: MANAGED_IDENTITY_CLIENT_ID not found. Run 'azd provision' first.${NC}"
    exit 1
}

AGENT_IDENTITY_CLIENT_ID=$(azd env get-value AGENT_IDENTITY_CLIENT_ID 2>/dev/null || azd env get-value BOT_MICROSOFT_APP_ID 2>/dev/null) || {
    echo -e "${RED}Error: AGENT_IDENTITY_CLIENT_ID not found. Was Phase 1 run?${NC}"
    exit 1
}

# Construct resource names (following azd conventions)
RESOURCE_GROUP="rg-$ENV_NAME"
BOT_NAME="bot-$ENV_NAME"
APP_SERVICE_NAME="app-$ENV_NAME"
APP_URL="https://$APP_SERVICE_NAME.azurewebsites.net"

# Get additional values if available
TENANT_ID=$(azd env get-value TENANT_ID 2>/dev/null || az account show --query tenantId -o tsv)

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
# The Admin needs these values for Step 3 (FIC) and Step 4 (Bot OAuth).
#
# =============================================================================

# Environment Info
AZURE_ENV_NAME=$ENV_NAME

# Tenant
TENANT_ID=$TENANT_ID

# Agent Identity (from Step 1 - needed for FIC and OAuth)
AGENT_IDENTITY_CLIENT_ID=$AGENT_IDENTITY_CLIENT_ID

# Managed Identity (from azd provision - needed for FIC)
MANAGED_IDENTITY_CLIENT_ID=$MANAGED_IDENTITY_CLIENT_ID

# Azure Resources (from azd provision - needed for Bot OAuth)
RESOURCE_GROUP=$RESOURCE_GROUP
BOT_NAME=$BOT_NAME
APP_SERVICE_NAME=$APP_SERVICE_NAME
APP_URL=$APP_URL

# =============================================================================
# ADMIN COMMANDS (Step 3 + 4)
# =============================================================================
# 
# Step 3 - Create FIC:
#   bash scripts/03-admin-create-fic.sh \\
#     --agent-identity-id $AGENT_IDENTITY_CLIENT_ID \\
#     --mi-client-id $MANAGED_IDENTITY_CLIENT_ID
#
# Step 4 - Bot OAuth:
#   bash scripts/04-admin-bot-oauth.sh \\
#     --bot-app-id $AGENT_IDENTITY_CLIENT_ID \\
#     --resource-group $RESOURCE_GROUP \\
#     --bot-name $BOT_NAME
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
echo "  2. Admin runs Step 3 and Step 4 scripts"
echo "  3. Then run: bash scripts/05-dev-teams-manifest.sh"
echo ""
