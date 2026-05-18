#!/bin/bash
# =============================================================================
# Cleanup Script - Remove All Deployment Resources
# =============================================================================
# This script removes all resources created by a deployment:
#   1. Azure resource group (and all contained resources)
#   2. Entra ID app registration
#   3. azd environment
#   4. Local credential files
#
# Usage: ./scripts/cleanup.sh --env <name>
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
        --help|-h)
            echo "Usage: $0 --env <name> [--force]"
            echo ""
            echo "Options:"
            echo "  --env <name>   Environment name to clean up (required)"
            echo "  --force, -f    Skip confirmation prompts"
            echo "  --help, -h     Show this help message"
            echo ""
            echo "This will delete:"
            echo "  - Azure resource group: rg-<name>"
            echo "  - App registration: <name>-StreamingBot"
            echo "  - azd environment: <name>"
            echo "  - Local credential files"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
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
echo -e "${YELLOW}║     Teams Streaming Bot - Cleanup Deployment                  ║${NC}"
echo -e "${YELLOW}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""

cd "$PROJECT_ROOT"

echo -e "${YELLOW}WARNING: This will permanently delete:${NC}"
echo "  - Resource group: rg-$ENV_NAME (and all Azure resources)"
echo "  - App registration: ${ENV_NAME}-StreamingBot"
echo "  - azd environment: $ENV_NAME"
echo "  - Local files: bot-credentials-${ENV_NAME}.txt"
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
    echo "  Deleting resource group: $RESOURCE_GROUP"
    az group delete --name "$RESOURCE_GROUP" --yes --no-wait
    echo -e "${GREEN}✓ Resource group deletion initiated (running in background)${NC}"
else
    echo -e "${YELLOW}⚠ Resource group not found: $RESOURCE_GROUP${NC}"
fi

# 2. Delete app registration
echo -e "${BLUE}[2/4] Deleting app registration...${NC}"
APP_DISPLAY_NAME="${ENV_NAME}-StreamingBot"
APP_ID=$(az ad app list --filter "displayName eq '${APP_DISPLAY_NAME}'" --query "[0].appId" -o tsv 2>/dev/null || echo "")

if [ -n "$APP_ID" ]; then
    echo "  Deleting app: $APP_DISPLAY_NAME ($APP_ID)"
    az ad app delete --id "$APP_ID"
    echo -e "${GREEN}✓ App registration deleted${NC}"
else
    echo -e "${YELLOW}⚠ App registration not found: $APP_DISPLAY_NAME${NC}"
fi

# 3. Delete azd environment
echo -e "${BLUE}[3/4] Deleting azd environment...${NC}"
if command -v azd &> /dev/null; then
    if azd env list 2>/dev/null | grep -q "^$ENV_NAME"; then
        azd env delete "$ENV_NAME" --force 2>/dev/null || true
        echo -e "${GREEN}✓ azd environment deleted${NC}"
    else
        echo -e "${YELLOW}⚠ azd environment not found: $ENV_NAME${NC}"
    fi
else
    echo -e "${YELLOW}⚠ azd not installed, skipping environment cleanup${NC}"
fi

# 4. Delete local credential files
echo -e "${BLUE}[4/4] Cleaning up local files...${NC}"
CRED_FILE="$PROJECT_ROOT/bot-credentials-${ENV_NAME}.txt"
if [ -f "$CRED_FILE" ]; then
    rm -f "$CRED_FILE"
    echo -e "${GREEN}✓ Deleted: $(basename $CRED_FILE)${NC}"
else
    echo -e "${YELLOW}⚠ Credentials file not found${NC}"
fi

# Clean up teams-manifest zip
MANIFEST_ZIP="$PROJECT_ROOT/teams-manifest/${ENV_NAME}*.zip"
for f in $MANIFEST_ZIP; do
    if [ -f "$f" ]; then
        rm -f "$f"
        echo -e "${GREEN}✓ Deleted: $(basename $f)${NC}"
    fi
done

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     Cleanup Complete!                                          ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Note: Resource group deletion may take a few minutes to complete.${NC}"
echo "To verify, check: az group exists --name rg-$ENV_NAME"
echo ""
