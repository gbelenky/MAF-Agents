#!/bin/bash
# =============================================================================
# STEP 0: Entra Admin - Cleanup App Registrations
# =============================================================================
# Role: ENTRA ADMIN
# Purpose: Remove app registrations to clean up or start fresh
# Run: OPTIONAL - use to reset before redeploying
#
# WARNING: This will permanently delete the app registrations!
#
# Usage:
#   ./00-admin-cleanup.sh [--prefix <app-prefix>] [--force]
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
echo "  Entra Admin - Cleanup App Registrations"
echo "=============================================="
echo -e "${NC}"

# Parse arguments
APP_PREFIX="OneDrive-Agent"
FORCE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --prefix)
            APP_PREFIX="$2"
            shift 2
            ;;
        --force)
            FORCE=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--prefix <app-prefix>] [--force]"
            echo ""
            echo "Options:"
            echo "  --prefix    Prefix for app registration names (default: OneDrive-Agent)"
            echo "  --force     Skip confirmation prompts"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Check if logged in
CURRENT_USER=$(az ad signed-in-user show --query displayName -o tsv 2>/dev/null) || {
    echo -e "${YELLOW}Not logged in. Please log in with admin credentials.${NC}"
    az login
    CURRENT_USER=$(az ad signed-in-user show --query displayName -o tsv)
}

echo -e "${GREEN}✓ Logged in as: $CURRENT_USER${NC}"

# Find apps to delete
BLUEPRINT_ID=$(az ad app list --display-name "${APP_PREFIX}-Blueprint" --query "[0].appId" -o tsv 2>/dev/null)
AGENT_ID=$(az ad app list --display-name "${APP_PREFIX}-Identity" --query "[0].appId" -o tsv 2>/dev/null)

echo ""
echo "Apps found with prefix '${APP_PREFIX}':"
echo ""

if [ -n "$BLUEPRINT_ID" ]; then
    echo -e "  ${YELLOW}Blueprint:${NC}       ${APP_PREFIX}-Blueprint ($BLUEPRINT_ID)"
else
    echo "  Blueprint:       (not found)"
fi

if [ -n "$AGENT_ID" ]; then
    echo -e "  ${YELLOW}Agent Identity:${NC}  ${APP_PREFIX}-Identity ($AGENT_ID)"
else
    echo "  Agent Identity:  (not found)"
fi

if [ -z "$BLUEPRINT_ID" ] && [ -z "$AGENT_ID" ]; then
    echo ""
    echo "No apps found to delete."
    exit 0
fi

echo ""
echo -e "${RED}WARNING: This will permanently delete these app registrations!${NC}"
echo ""

if [ "$FORCE" != true ]; then
    read -p "Are you sure you want to delete these apps? (type 'DELETE' to confirm): " CONFIRM
    if [ "$CONFIRM" != "DELETE" ]; then
        echo "Aborted."
        exit 0
    fi
fi

echo ""

# Delete Blueprint app
if [ -n "$BLUEPRINT_ID" ]; then
    echo -e "${BLUE}Deleting Blueprint app...${NC}"
    az ad app delete --id "$BLUEPRINT_ID" 2>/dev/null && \
        echo -e "${GREEN}✓ Deleted: ${APP_PREFIX}-Blueprint${NC}" || \
        echo -e "${RED}✗ Failed to delete Blueprint app${NC}"
fi

# Delete Agent Identity app
if [ -n "$AGENT_ID" ]; then
    echo -e "${BLUE}Deleting Agent Identity app...${NC}"
    az ad app delete --id "$AGENT_ID" 2>/dev/null && \
        echo -e "${GREEN}✓ Deleted: ${APP_PREFIX}-Identity${NC}" || \
        echo -e "${RED}✗ Failed to delete Agent Identity app${NC}"
fi

echo ""
echo -e "${GREEN}Cleanup complete.${NC}"
echo ""
echo "Note: Deleted apps are moved to 'Deleted applications' in Entra ID"
echo "and will be permanently removed after 30 days."
echo ""
