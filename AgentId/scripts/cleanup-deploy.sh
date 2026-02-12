#!/bin/bash
#===============================================================================
# Cleanup Script for OneDrive Agent Deployment
#===============================================================================
# This script removes all resources created by a deployment:
#   1. Azure resource group (and all contained resources)
#   2. Entra ID app registrations
#   3. azd environment
#
# Usage: ./scripts/cleanup-deploy.sh --env <name>
#===============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

ENV_NAME=""
FORCE="false"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --env)
            ENV_NAME="$2"
            shift 2
            ;;
        --force|-f)
            FORCE="true"
            shift
            ;;
        --help)
            echo "Usage: $0 --env <name> [--force]"
            echo ""
            echo "Options:"
            echo "  --env <name>   Environment name to clean up"
            echo "  --force, -f    Skip confirmation prompts"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

if [ -z "$ENV_NAME" ]; then
    echo -e "${RED}Error: --env is required${NC}"
    echo "Usage: $0 --env <name>"
    exit 1
fi

echo ""
echo -e "${YELLOW}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║     OneDrive Agent - Cleanup Deployment                       ║${NC}"
echo -e "${YELLOW}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${YELLOW}WARNING: This will permanently delete:${NC}"
echo "  - Resource group: rg-$ENV_NAME (and all Azure resources)"
echo "  - App registration: ${ENV_NAME}-Blueprint"
echo "  - App registration: ${ENV_NAME}-Identity"
echo "  - azd environment: $ENV_NAME"
echo ""

if [ "$FORCE" != "true" ]; then
    read -p "Are you sure you want to continue? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Cancelled."
        exit 0
    fi
fi

echo ""

# 1. Delete Azure resource group
echo -e "${BLUE}[1/4] Deleting Azure resource group...${NC}"
RESOURCE_GROUP="rg-$ENV_NAME"
if az group exists --name "$RESOURCE_GROUP" 2>/dev/null | grep -q "true"; then
    az group delete --name "$RESOURCE_GROUP" --yes --no-wait
    echo -e "${GREEN}✓ Resource group deletion initiated (running in background)${NC}"
else
    echo -e "${YELLOW}⚠ Resource group not found: $RESOURCE_GROUP${NC}"
fi

# 2. Delete Blueprint app registration
echo -e "${BLUE}[2/4] Deleting Blueprint app registration...${NC}"
BLUEPRINT_ID=$(az ad app list --filter "displayName eq '${ENV_NAME}-Blueprint'" --query "[0].appId" -o tsv 2>/dev/null)
if [ -n "$BLUEPRINT_ID" ]; then
    az ad app delete --id "$BLUEPRINT_ID" 2>/dev/null || true
    echo -e "${GREEN}✓ Deleted Blueprint app: $BLUEPRINT_ID${NC}"
else
    echo -e "${YELLOW}⚠ Blueprint app not found: ${ENV_NAME}-Blueprint${NC}"
fi

# 3. Delete Agent Identity app registration
echo -e "${BLUE}[3/4] Deleting Agent Identity app registration...${NC}"
AGENT_ID=$(az ad app list --filter "displayName eq '${ENV_NAME}-Identity'" --query "[0].appId" -o tsv 2>/dev/null)
if [ -n "$AGENT_ID" ]; then
    az ad app delete --id "$AGENT_ID" 2>/dev/null || true
    echo -e "${GREEN}✓ Deleted Agent Identity app: $AGENT_ID${NC}"
else
    echo -e "${YELLOW}⚠ Agent Identity app not found: ${ENV_NAME}-Identity${NC}"
fi

# 4. Delete azd environment
echo -e "${BLUE}[4/4] Deleting azd environment...${NC}"
cd "$PROJECT_DIR"
if azd env list 2>/dev/null | grep -q "$ENV_NAME"; then
    # Switch to different env if this is default
    CURRENT_DEFAULT=$(azd env list 2>/dev/null | grep "true" | awk '{print $1}')
    if [ "$CURRENT_DEFAULT" = "$ENV_NAME" ]; then
        # Find another env to make default, or leave empty
        OTHER_ENV=$(azd env list 2>/dev/null | grep "false" | head -1 | awk '{print $1}')
        if [ -n "$OTHER_ENV" ]; then
            azd env select "$OTHER_ENV" 2>/dev/null || true
        fi
    fi
    
    # Remove the .azure/ENV_NAME directory
    rm -rf ".azure/$ENV_NAME" 2>/dev/null || true
    echo -e "${GREEN}✓ Deleted azd environment: $ENV_NAME${NC}"
else
    echo -e "${YELLOW}⚠ azd environment not found: $ENV_NAME${NC}"
fi

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              ✅ CLEANUP COMPLETE                              ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Note: Azure resource group deletion runs in background.${NC}"
echo -e "${YELLOW}It may take a few minutes to complete.${NC}"
echo ""
