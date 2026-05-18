#!/bin/bash
# =============================================================================
# STEP 4: Developer - Generate Teams App Manifest
# =============================================================================
# Role: DEVELOPER
# Purpose: Generate Teams app manifest and zip package for upload
#
# Prerequisites:
#   - Azure deployment completed (Step 2)
#   - Admin granted RBAC access (Step 3)
#   - Icon files in appManifest/ folder (color.png, outline.png)
#
# Usage:
#   bash scripts/04-dev-teams-manifest.sh
#
# Output: teams-manifest/{BotName}.zip
#
# This script uses template and substitutes placeholders:
#   {{BOT_ID}} -> Bot Microsoft App ID
#   {{BOT_DOMAIN}} -> App Service hostname
#   {{BOT_NAME}} -> Short bot name
#   {{BOT_NAME_FULL}} -> Full bot name
#   {{MANIFEST_VERSION}} -> Version number
#
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo ""
echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     Teams Streaming Bot - Generate Manifest                   ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""

cd "$PROJECT_ROOT"

# Try to get values from azd environment
if command -v azd &> /dev/null; then
    AZD_ENV_NAME=$(azd env get-value AZURE_ENV_NAME 2>&1 | grep -v "^ERROR\|^WARNING\|update\|winget" | head -1 || echo "")
    BOT_ID=$(azd env get-value BOT_ID 2>&1 | grep -v "^ERROR\|^WARNING\|update\|winget" | head -1 || echo "")
    APP_HOSTNAME=$(azd env get-value APP_SERVICE_HOSTNAME 2>&1 | grep -v "^ERROR\|^WARNING\|update\|winget" | head -1 || echo "")
    
    # Derive hostname from env name if not set
    if [ -z "$APP_HOSTNAME" ] && [ -n "$AZD_ENV_NAME" ]; then
        APP_HOSTNAME="app-${AZD_ENV_NAME}.azurewebsites.net"
    fi
fi

# Fallback: Try to load from credentials file
if [ -z "$BOT_ID" ]; then
    for f in bot-credentials-*.txt; do
        if [ -f "$f" ]; then
            echo "Found credentials file: $f"
            FILE_BOT_ID=$(grep "^BOT_ID=" "$f" | cut -d'=' -f2)
            FILE_BOT_NAME=$(grep "^BOT_NAME=" "$f" | cut -d'=' -f2)
            if [ -n "$FILE_BOT_ID" ]; then
                BOT_ID="$FILE_BOT_ID"
                echo "  ✓ BOT_ID from file"
            fi
            if [ -z "$AZD_ENV_NAME" ] && [ -n "$FILE_BOT_NAME" ]; then
                AZD_ENV_NAME="$FILE_BOT_NAME"
                APP_HOSTNAME="app-${AZD_ENV_NAME}.azurewebsites.net"
            fi
            break
        fi
    done
fi

# Set default values
MANIFEST_VERSION="${MANIFEST_VERSION:-1.0.0}"

# Derive bot name from environment name
if [ -n "$AZD_ENV_NAME" ]; then
    # Capitalize first letter (e.g., streamingbot -> StreamingBot)
    BOT_NAME=$(echo "$AZD_ENV_NAME" | sed -E 's/(^|-)([a-z])/\U\2/g' | sed 's/-//g')
else
    BOT_NAME="StreamingBot"
fi
BOT_NAME_FULL="${BOT_NAME} - AI Streaming Assistant"

# Prompt for missing values
if [ -z "$BOT_ID" ]; then
    echo -e "${YELLOW}BOT_ID not found.${NC}"
    echo "  Check credentials file or azd environment"
    read -p "Enter Bot Microsoft App ID: " BOT_ID
fi

if [ -z "$APP_HOSTNAME" ]; then
    echo -e "${YELLOW}APP_HOSTNAME not found.${NC}"
    echo "  Typically: app-\$AZURE_ENV_NAME.azurewebsites.net"
    read -p "Enter App Service hostname: " APP_HOSTNAME
fi

# Summary
echo -e "${BLUE}Configuration:${NC}"
echo "  Bot ID:          $BOT_ID"
echo "  Bot Name:        $BOT_NAME"
echo "  Bot Name Full:   $BOT_NAME_FULL"
echo "  App Hostname:    $APP_HOSTNAME"
echo "  Version:         $MANIFEST_VERSION"
echo ""

# Create teams-manifest directory
MANIFEST_DIR="$PROJECT_ROOT/teams-manifest"
mkdir -p "$MANIFEST_DIR"

# Check for template file
TEMPLATE_FILE="$PROJECT_ROOT/appManifest/manifest.json.template"
if [ ! -f "$TEMPLATE_FILE" ]; then
    # Use existing manifest.json as base if template doesn't exist
    TEMPLATE_FILE="$PROJECT_ROOT/appManifest/manifest.json"
fi

if [ ! -f "$TEMPLATE_FILE" ]; then
    echo -e "${RED}Error: No manifest template found in appManifest/${NC}"
    exit 1
fi

echo -e "${BLUE}Generating manifest.json...${NC}"

# Read template and substitute placeholders
MANIFEST_CONTENT=$(cat "$TEMPLATE_FILE")
MANIFEST_CONTENT=$(echo "$MANIFEST_CONTENT" | sed "s/<<BOT_ID>>/$BOT_ID/g")
MANIFEST_CONTENT=$(echo "$MANIFEST_CONTENT" | sed "s/{{BOT_ID}}/$BOT_ID/g")
MANIFEST_CONTENT=$(echo "$MANIFEST_CONTENT" | sed "s/<<BOT_DOMAIN>>/$APP_HOSTNAME/g")
MANIFEST_CONTENT=$(echo "$MANIFEST_CONTENT" | sed "s/{{BOT_DOMAIN}}/$APP_HOSTNAME/g")
MANIFEST_CONTENT=$(echo "$MANIFEST_CONTENT" | sed "s/{{BOT_NAME}}/$BOT_NAME/g")
MANIFEST_CONTENT=$(echo "$MANIFEST_CONTENT" | sed "s/{{BOT_NAME_FULL}}/$BOT_NAME_FULL/g")
MANIFEST_CONTENT=$(echo "$MANIFEST_CONTENT" | sed "s/{{MANIFEST_VERSION}}/$MANIFEST_VERSION/g")

# Write manifest
echo "$MANIFEST_CONTENT" > "$MANIFEST_DIR/manifest.json"
echo -e "${GREEN}✓ manifest.json created${NC}"

# Copy or create icon files
echo -e "${BLUE}Processing icon files...${NC}"

# Color icon (192x192)
if [ -f "$PROJECT_ROOT/appManifest/color.png" ]; then
    cp "$PROJECT_ROOT/appManifest/color.png" "$MANIFEST_DIR/"
    echo -e "${GREEN}✓ color.png copied${NC}"
elif [ -f "$MANIFEST_DIR/color.png" ]; then
    echo -e "${YELLOW}⚠ Using existing color.png${NC}"
else
    echo -e "${YELLOW}⚠ color.png not found - creating placeholder${NC}"
    # Create a simple placeholder (requires ImageMagick or similar)
    if command -v convert &> /dev/null; then
        convert -size 192x192 xc:#5B5FC7 -gravity center -pointsize 48 -fill white -annotate 0 "BOT" "$MANIFEST_DIR/color.png"
    else
        echo -e "${RED}  Please add color.png (192x192) to appManifest/ or teams-manifest/${NC}"
    fi
fi

# Outline icon (32x32)
if [ -f "$PROJECT_ROOT/appManifest/outline.png" ]; then
    cp "$PROJECT_ROOT/appManifest/outline.png" "$MANIFEST_DIR/"
    echo -e "${GREEN}✓ outline.png copied${NC}"
elif [ -f "$MANIFEST_DIR/outline.png" ]; then
    echo -e "${YELLOW}⚠ Using existing outline.png${NC}"
else
    echo -e "${YELLOW}⚠ outline.png not found - creating placeholder${NC}"
    if command -v convert &> /dev/null; then
        convert -size 32x32 xc:transparent -gravity center -pointsize 12 -fill black -annotate 0 "B" "$MANIFEST_DIR/outline.png"
    else
        echo -e "${RED}  Please add outline.png (32x32) to appManifest/ or teams-manifest/${NC}"
    fi
fi

# Create zip package
echo ""
echo -e "${BLUE}Creating zip package...${NC}"

ZIP_NAME="${BOT_NAME}.zip"
cd "$MANIFEST_DIR"

# Remove old zip if exists
rm -f "$ZIP_NAME"

# Check for required files
MISSING_FILES=0
for file in manifest.json color.png outline.png; do
    if [ ! -f "$file" ]; then
        echo -e "${RED}✗ Missing: $file${NC}"
        MISSING_FILES=$((MISSING_FILES + 1))
    fi
done

if [ $MISSING_FILES -gt 0 ]; then
    echo ""
    echo -e "${RED}Cannot create zip - missing required files.${NC}"
    echo "Please add the missing files to teams-manifest/ or appManifest/"
    exit 1
fi

# Create zip
zip -q "$ZIP_NAME" manifest.json color.png outline.png
echo -e "${GREEN}✓ Created: teams-manifest/$ZIP_NAME${NC}"

cd "$PROJECT_ROOT"

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     Teams Manifest Generated Successfully!                    ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "Package: ${BLUE}teams-manifest/$ZIP_NAME${NC}"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "  Upload the zip file to Teams:"
echo ""
echo "  Option 1: Teams Admin Center (recommended for org-wide)"
echo "    1. Go to https://admin.teams.microsoft.com"
echo "    2. Navigate to Teams apps > Manage apps"
echo "    3. Click 'Upload new app'"
echo "    4. Select teams-manifest/$ZIP_NAME"
echo ""
echo "  Option 2: Sideload in Teams (for testing)"
echo "    1. Open Teams"
echo "    2. Go to Apps > Manage your apps"
echo "    3. Click 'Upload an app' > 'Upload a custom app'"
echo "    4. Select teams-manifest/$ZIP_NAME"
echo ""
