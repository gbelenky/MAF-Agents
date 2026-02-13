#!/bin/bash
# =============================================================================
# STEP 0: Entra Admin - Cleanup App Registration
# =============================================================================
# Role: ENTRA ADMIN
# Purpose: Remove app registration to clean up or start fresh
# Run: OPTIONAL - use to reset before redeploying
#
# WARNING: This will permanently delete the app registration!
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
echo "  Entra Admin - Cleanup App Registration"
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
            echo "  --prefix    Prefix for app registration name (default: OneDrive-Agent)"
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

# Find app to delete (try both naming conventions)
APP_ID=$(az ad app list --display-name "${APP_PREFIX}-Agent" --query "[0].appId" -o tsv 2>/dev/null)
APP_NAME="${APP_PREFIX}-Agent"

# Also check for old naming convention
if [ -z "$APP_ID" ]; then
    APP_ID=$(az ad app list --display-name "${APP_PREFIX}-Identity" --query "[0].appId" -o tsv 2>/dev/null)
    APP_NAME="${APP_PREFIX}-Identity"
fi

echo ""
echo "Apps found with prefix '${APP_PREFIX}':"
echo ""

if [ -n "$APP_ID" ]; then
    echo -e "  ${YELLOW}App:${NC} ${APP_NAME} ($APP_ID)"
else
    echo "  (none found)"
    echo ""
    echo "No apps found to delete."
    exit 0
fi

echo ""
echo -e "${RED}WARNING: This will permanently delete this app registration!${NC}"
echo ""

if [ "$FORCE" != true ]; then
    read -p "Are you sure you want to delete this app? (type 'DELETE' to confirm): " CONFIRM
    if [ "$CONFIRM" != "DELETE" ]; then
        echo "Aborted."
        exit 0
    fi
fi

echo ""

# Delete app
if [ -n "$APP_ID" ]; then
    echo -e "${BLUE}Deleting app...${NC}"
    az ad app delete --id "$APP_ID" 2>/dev/null && \
        echo -e "${GREEN}✓ Deleted: ${APP_NAME}${NC}" || \
        echo -e "${RED}✗ Failed to delete app${NC}"
fi

echo ""
echo -e "${GREEN}Cleanup complete.${NC}"
echo ""
echo "Note: Deleted apps are moved to 'Deleted applications' in Entra ID"
echo "and will be permanently removed after 30 days."
echo ""
