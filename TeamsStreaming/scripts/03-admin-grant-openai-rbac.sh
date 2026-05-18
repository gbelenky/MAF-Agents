#!/bin/bash
# =============================================================================
# STEP 3: Admin - Grant Azure OpenAI RBAC Access
# =============================================================================
# Role: ADMIN (Azure subscription owner or User Access Administrator)
# Purpose: Grant Managed Identity access to Azure OpenAI resource
# Run: AFTER developer runs 'azd up' and shares 02-dev-handoff-{env}.txt
#
# Prerequisites:
#   - Azure CLI installed
#   - Logged in with Admin privileges (RBAC assignment rights)
#   - Developer completed azd up (Managed Identity created)
#
# Usage:
#   ./03-admin-grant-openai-rbac.sh [options]
#
# Options:
#   --handoff-file <path>     Developer handoff file (02-dev-handoff-*.txt)  
#   --mi-principal-id <id>    Managed Identity Principal ID
#   --openai-resource-id <id> Azure OpenAI resource ID
#   --openai-rg <name>        Azure OpenAI resource group
#   --openai-account <name>   Azure OpenAI account name
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

echo -e "${BLUE}"
echo "=============================================="
echo "  STEP 3: Admin - Grant Azure OpenAI Access"
echo "=============================================="
echo -e "${NC}"

# Parse arguments
MI_PRINCIPAL_ID=""
OPENAI_RESOURCE_ID=""
OPENAI_RG=""
OPENAI_ACCOUNT=""
HANDOFF_FILE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --handoff-file)
            HANDOFF_FILE="$2"
            shift 2
            ;;
        --mi-principal-id)
            MI_PRINCIPAL_ID="$2"
            shift 2
            ;;
        --openai-resource-id)
            OPENAI_RESOURCE_ID="$2"
            shift 2
            ;;
        --openai-rg)
            OPENAI_RG="$2"
            shift 2
            ;;
        --openai-account)
            OPENAI_ACCOUNT="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --handoff-file <path>     Developer handoff file"
            echo "  --mi-principal-id <id>    Managed Identity Principal ID"
            echo "  --openai-resource-id <id> Full Azure OpenAI resource ID"
            echo "  --openai-rg <name>        Azure OpenAI resource group"
            echo "  --openai-account <name>   Azure OpenAI account name"
            echo ""
            echo "Examples:"
            echo "  $0 --handoff-file handoff/02-dev-handoff-myenv.txt \\"
            echo "     --openai-rg rg-openai --openai-account my-openai"
            echo ""
            echo "  $0 --mi-principal-id abc-123 \\"
            echo "     --openai-resource-id /subscriptions/.../Microsoft.CognitiveServices/accounts/my-openai"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Try to load from handoff file if available
ADMIN_INPUT_FILE=""
if [ -n "$HANDOFF_FILE" ] && [ -f "$HANDOFF_FILE" ]; then
    ADMIN_INPUT_FILE="$HANDOFF_FILE"
elif [ -n "$HANDOFF_FILE" ]; then
    echo -e "${RED}Error: Handoff file not found: $HANDOFF_FILE${NC}"
    exit 1
else
    # Search for handoff files
    for f in handoff/02-dev-handoff-*.txt 02-dev-handoff-*.txt; do
        if [ -f "$f" ]; then
            ADMIN_INPUT_FILE="$f"
            break
        fi
    done
fi

if [ -n "$ADMIN_INPUT_FILE" ]; then
    echo -e "${GREEN}✓ Found handoff file: $ADMIN_INPUT_FILE${NC}"
    
    if [ -z "$MI_PRINCIPAL_ID" ]; then
        FILE_MI_ID=$(grep "^MI_PRINCIPAL_ID=" "$ADMIN_INPUT_FILE" | cut -d'=' -f2)
        if [ -n "$FILE_MI_ID" ]; then
            MI_PRINCIPAL_ID="$FILE_MI_ID"
            echo -e "${GREEN}  ✓ MI_PRINCIPAL_ID from file${NC}"
        fi
    fi
fi

# Check Azure CLI
if ! command -v az &> /dev/null; then
    echo -e "${RED}Error: Azure CLI is not installed.${NC}"
    exit 1
fi

# Check login
CURRENT_USER=$(az ad signed-in-user show --query displayName -o tsv 2>/dev/null) || {
    echo -e "${YELLOW}Not logged in. Please log in with admin credentials.${NC}"
    az login
    CURRENT_USER=$(az ad signed-in-user show --query displayName -o tsv)
}
echo -e "${GREEN}✓ Logged in as: $CURRENT_USER${NC}"

# Validate MI Principal ID
if [ -z "$MI_PRINCIPAL_ID" ]; then
    echo -e "${RED}Error: MI_PRINCIPAL_ID is required.${NC}"
    echo "Provide via --mi-principal-id or --handoff-file"
    exit 1
fi

# Build OpenAI resource ID if not provided
if [ -z "$OPENAI_RESOURCE_ID" ]; then
    if [ -z "$OPENAI_RG" ] || [ -z "$OPENAI_ACCOUNT" ]; then
        echo ""
        echo -e "${YELLOW}Azure OpenAI resource information needed.${NC}"
        echo ""
        
        if [ -z "$OPENAI_RG" ]; then
            read -p "Enter Azure OpenAI Resource Group: " OPENAI_RG
        fi
        
        if [ -z "$OPENAI_ACCOUNT" ]; then
            read -p "Enter Azure OpenAI Account Name: " OPENAI_ACCOUNT
        fi
    fi
    
    SUBSCRIPTION_ID=$(az account show --query id -o tsv)
    OPENAI_RESOURCE_ID="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$OPENAI_RG/providers/Microsoft.CognitiveServices/accounts/$OPENAI_ACCOUNT"
fi

echo ""
echo -e "${BLUE}Granting access with:${NC}"
echo "  MI Principal ID: $MI_PRINCIPAL_ID"
echo "  OpenAI Resource: $OPENAI_RESOURCE_ID"
echo ""

# IMPORTANT: Use PowerShell on Windows to avoid Git Bash path mangling
echo -e "${BLUE}Creating role assignment...${NC}"
echo -e "${YELLOW}Note: Using pwsh to avoid Git Bash path issues${NC}"
echo ""

# Check if pwsh is available
if command -v pwsh &> /dev/null; then
    pwsh -Command "az role assignment create \
        --assignee-object-id '$MI_PRINCIPAL_ID' \
        --assignee-principal-type ServicePrincipal \
        --role 'Cognitive Services OpenAI User' \
        --scope '$OPENAI_RESOURCE_ID' \
        --query roleDefinitionName -o tsv"
    
    if [ $? -eq 0 ]; then
        echo ""
        echo -e "${GREEN}✓ Role assignment created successfully!${NC}"
    else
        echo -e "${RED}Error: Failed to create role assignment${NC}"
        exit 1
    fi
else
    echo -e "${YELLOW}PowerShell (pwsh) not found. Trying az directly...${NC}"
    echo -e "${YELLOW}If this fails with path errors, run manually in PowerShell:${NC}"
    echo ""
    echo "az role assignment create \`"
    echo "  --assignee-object-id '$MI_PRINCIPAL_ID' \`"
    echo "  --assignee-principal-type ServicePrincipal \`"
    echo "  --role 'Cognitive Services OpenAI User' \`"
    echo "  --scope '$OPENAI_RESOURCE_ID'"
    echo ""
    
    az role assignment create \
        --assignee-object-id "$MI_PRINCIPAL_ID" \
        --assignee-principal-type ServicePrincipal \
        --role "Cognitive Services OpenAI User" \
        --scope "$OPENAI_RESOURCE_ID" \
        --query roleDefinitionName -o tsv
fi

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Step 3 Complete!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "The Managed Identity now has access to Azure OpenAI."
echo ""
echo "Next Steps:"
echo "  1. Notify Developer that RBAC is configured"
echo "  2. Developer runs: bash scripts/04-dev-teams-manifest.sh"
echo ""
