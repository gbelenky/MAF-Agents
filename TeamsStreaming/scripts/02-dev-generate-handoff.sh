#!/bin/bash
# =============================================================================
# STEP 2: Developer - Generate Handoff File for Admin
# =============================================================================
# Role: DEVELOPER
# Purpose: Generate file with azd deployment values for Admin
# Run: AFTER 'azd provision' (or 'azd up') completes
#
# Output: handoff/02-dev-handoff-{env}.txt → share with Admin
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

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

# Get App Service name (from azd output or derive it)
SERVICE_BOT_NAME=$(azd env get-value SERVICE_BOT_NAME 2>/dev/null || echo "")
if [ -z "$SERVICE_BOT_NAME" ]; then
    echo -e "${RED}Error: SERVICE_BOT_NAME not found. Run 'azd up' first.${NC}"
    exit 1
fi

# Get resource group
RESOURCE_GROUP="rg-$ENV_NAME"

# Get Managed Identity Principal ID
echo -e "${BLUE}Retrieving Managed Identity...${NC}"
MI_PRINCIPAL_ID=$(az webapp identity show --name "$SERVICE_BOT_NAME" --resource-group "$RESOURCE_GROUP" --query principalId -o tsv 2>/dev/null) || {
    echo -e "${RED}Error: Could not get Managed Identity. Is the App Service deployed?${NC}"
    exit 1
}

MI_CLIENT_ID=$(az webapp identity show --name "$SERVICE_BOT_NAME" --resource-group "$RESOURCE_GROUP" --query clientId -o tsv 2>/dev/null || echo "")

echo -e "${GREEN}✓ Managed Identity Principal ID: $MI_PRINCIPAL_ID${NC}"

# Get Bot ID
BOT_ID=$(azd env get-value BOT_ID 2>/dev/null || echo "")
if [ -z "$BOT_ID" ]; then
    echo -e "${YELLOW}Warning: BOT_ID not found in azd env${NC}"
fi

# Get tenant
TENANT_ID=$(az account show --query tenantId -o tsv)

# Get subscription
SUBSCRIPTION_ID=$(az account show --query id -o tsv)

# Get App URL
APP_URL=$(azd env get-value SERVICE_BOT_URL 2>/dev/null || echo "https://$SERVICE_BOT_NAME.azurewebsites.net")

# Get Azure OpenAI endpoint
AZURE_OPENAI_ENDPOINT=$(azd env get-value AZURE_OPENAI_ENDPOINT 2>/dev/null || echo "")

# Generate output file
mkdir -p handoff
OUTPUT_FILE="handoff/02-dev-handoff-$ENV_NAME.txt"
cat > "$OUTPUT_FILE" << EOF
# =============================================================================
# Step 2: Developer Handoff for Admin
# =============================================================================
# Environment: $ENV_NAME
# Generated: $(date)
# 
# Share this file securely with the Admin.
# The Admin needs to grant Azure OpenAI access to the Managed Identity.
#
# =============================================================================

# Environment Info
AZURE_ENV_NAME=$ENV_NAME
TENANT_ID=$TENANT_ID
SUBSCRIPTION_ID=$SUBSCRIPTION_ID

# Bot Info
BOT_ID=$BOT_ID

# App Service
SERVICE_BOT_NAME=$SERVICE_BOT_NAME
RESOURCE_GROUP=$RESOURCE_GROUP
APP_URL=$APP_URL

# Managed Identity (Admin needs this for RBAC)
MI_PRINCIPAL_ID=$MI_PRINCIPAL_ID
MI_CLIENT_ID=$MI_CLIENT_ID

# Azure OpenAI (Admin needs this for RBAC scope)
AZURE_OPENAI_ENDPOINT=$AZURE_OPENAI_ENDPOINT

# =============================================================================
# ADMIN COMMAND (Step 3)
# =============================================================================
# 
# The Admin should run (in PowerShell to avoid Git Bash path issues):
#
# pwsh -Command "az role assignment create \\
#   --assignee-object-id '$MI_PRINCIPAL_ID' \\
#   --assignee-principal-type ServicePrincipal \\
#   --role 'Cognitive Services OpenAI User' \\
#   --scope '<AZURE_OPENAI_RESOURCE_ID>'"
#
# Or use the script:
#   bash scripts/03-admin-grant-openai-rbac.sh --handoff-file handoff/02-dev-handoff-$ENV_NAME.txt
#
# =============================================================================
EOF

echo ""
echo -e "${GREEN}✓ Generated: $OUTPUT_FILE${NC}"
echo ""
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}  SHARE THIS FILE WITH THE ADMIN${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
cat "$OUTPUT_FILE"
echo ""
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Next Steps:"
echo "  1. Send '$OUTPUT_FILE' to the Admin (securely!)"
echo "  2. Admin runs: bash scripts/03-admin-grant-openai-rbac.sh"
echo "  3. Then run: bash scripts/04-dev-teams-manifest.sh"
echo ""
