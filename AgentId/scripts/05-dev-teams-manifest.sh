#!/bin/bash
# =============================================================================
# STEP 5: Developer - Generate Teams App Manifest
# =============================================================================
# Role: DEVELOPER
# Purpose: Generate Teams app manifest and zip package for upload
# Run: AFTER Entra Admin completes Steps 3 and 4
#
# Output: teams-manifest/OneDriveAgent.zip → upload to Teams Admin Center
#
# This script uses template files and substitutes placeholders:
#   {{BOT_APP_ID}} -> Bot Microsoft App ID
#   {{APP_HOSTNAME}} -> App Service hostname
#   {{MANIFEST_VERSION}} -> Manifest version (default: 1.0.0)
#   {{AGENT_NAME}} -> Short agent name
#   {{AGENT_NAME_FULL}} -> Full agent name
#
# =============================================================================

set -e

# Determine script directory for relative paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=========================================="
echo "Teams App Manifest Generator"
echo "=========================================="

# Try to get values from azd environment if available
if command -v azd &> /dev/null; then
    AZD_ENV_NAME=$(azd env get-value AZURE_ENV_NAME 2>/dev/null || echo "")
    if [ -z "$BOT_MICROSOFT_APP_ID" ]; then
        BOT_MICROSOFT_APP_ID=$(azd env get-value BOT_MICROSOFT_APP_ID 2>/dev/null || echo "")
    fi
    if [ -z "$APP_SERVICE_HOSTNAME" ]; then
        # Derive from environment name
        APP_SERVICE_HOSTNAME="app-${AZD_ENV_NAME}.azurewebsites.net"
    fi
fi

# Get values from environment or prompt
BOT_APP_ID="${BOT_MICROSOFT_APP_ID:-}"
APP_HOSTNAME="${APP_SERVICE_HOSTNAME:-}"
MANIFEST_VERSION="${MANIFEST_VERSION:-1.0.0}"

# Derive agent name from azd environment if not explicitly set
if [ -z "$AGENT_NAME" ] && [ -n "$AZD_ENV_NAME" ]; then
    # Capitalize first letter of each word in env name (e.g., onedriveagent2 -> OneDriveAgent2)
    AGENT_NAME=$(echo "$AZD_ENV_NAME" | sed -E 's/(^|-)([a-z])/\U\2/g' | sed 's/-//g')
    echo "Using agent name from azd environment: $AGENT_NAME"
fi
AGENT_NAME="${AGENT_NAME:-OneDrive Agent}"
AGENT_NAME_FULL="${AGENT_NAME_FULL:-$AGENT_NAME - AI File Assistant}"

# Prompt for missing values
if [ -z "$BOT_APP_ID" ]; then
    echo "BOT_MICROSOFT_APP_ID not set."
    read -p "Enter Bot Microsoft App ID: " BOT_APP_ID
fi

if [ -z "$APP_HOSTNAME" ]; then
    echo "APP_SERVICE_HOSTNAME not set."
    read -p "Enter App Service hostname (e.g., app-myenv.azurewebsites.net): " APP_HOSTNAME
fi

# Validate inputs
if [ -z "$BOT_APP_ID" ] || [ -z "$APP_HOSTNAME" ]; then
    echo "Error: Both BOT_APP_ID and APP_HOSTNAME are required."
    exit 1
fi

# Manifest directory
MANIFEST_DIR="$PROJECT_ROOT/teams-manifest"
mkdir -p "$MANIFEST_DIR"

echo ""
echo "Creating manifest with:"
echo "  Agent Name: $AGENT_NAME"
echo "  Bot App ID: $BOT_APP_ID"
echo "  App Hostname: $APP_HOSTNAME"
echo "  Version: $MANIFEST_VERSION"
echo ""

# Check for template files
MANIFEST_TEMPLATE="$MANIFEST_DIR/manifest.json.template"

if [ ! -f "$MANIFEST_TEMPLATE" ]; then
    echo "Error: Template file not found: $MANIFEST_TEMPLATE"
    echo "Please ensure the template files exist in the teams-manifest folder."
    exit 1
fi

# Generate manifest.json from template
echo "Processing: manifest.json.template"
sed -e "s/{{BOT_APP_ID}}/$BOT_APP_ID/g" \
    -e "s/{{APP_HOSTNAME}}/$APP_HOSTNAME/g" \
    -e "s/{{MANIFEST_VERSION}}/$MANIFEST_VERSION/g" \
    -e "s/{{AGENT_NAME_FULL}}/$AGENT_NAME_FULL/g" \
    -e "s/{{AGENT_NAME}}/$AGENT_NAME/g" \
    "$MANIFEST_TEMPLATE" > "$MANIFEST_DIR/manifest.json"
echo "Created: $MANIFEST_DIR/manifest.json"

# Check for icons, create placeholders if missing
if [ ! -f "$MANIFEST_DIR/color.png" ]; then
    echo "Creating placeholder: color.png (192x192)"
    # Create a simple placeholder icon using base64
    echo "iVBORw0KGgoAAAANSUhEUgAAAMAAAADACAMAAABlApw1AAAABGdBTUEAALGPC/xhBQAAAAFzUkdC
AK7OHOkAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAAwUExURUdwTP///////////////////////////////
////////////////////////////////zlZJZsAAAAPdFJOUwAQIDBAUGBwgI+fv8/f7/PxlIAAAAMw
SURBVHja7d3bkqMwDEXRoP//z06GzCSTGAy2bEnF3k/TVNdaGNuSDYQAAAAAAAAAAAAA8J/bv0pZ
y6v8+jN5Xl5/JS/LPy+/kp/ll1/Jz/KyLH+XvJbfW17Lr+RneVn+LnktLy1vW17Lr+Rn+Vn+Lnkt
v5af5af5Wf4ueS0vLW9bXsuv5Gf5af4ueS1/rb+Wn+Vn+bvktfy1/lp+lp/l75LX8tf6a/lZfpa/
S17LX+uv5Wf5Wf4ueS1/rb+Wn+Vn+bvktfy1/lp+lp/l75LX8tf6a/lZfpa/S17LX+uv5Wf5Wf4u
eS1/rb+Wn+Vn+bvktfy1/lp+lp/l75LX8tf6a/lZfpa/S17LX+uv5Wf5Wf4ueS1/rb+Wn+Vn+bvk
tfy1/lp+lp/l75InAAAAAAAAAAAAAAAAAAAAAAAAAOCP/ZLv16f8Y/xbv+X7w/w7+fL8K/lx/p18
eX6Wvy35eX6Wv03yWn6Wv03yWn6Wv03yWn6Wv035Wv627z35eX6Wv+0bS36Wn+VvS36Wn+VvS36W
n+VvS36Wn+VvS36Wn+VvS36Wn+VvS36Wn+VvS36Wn+VvS36Wn+VvS36Wn+VvS36Wn+VvS36Wn+Vv
S36Wn+VvS36Wn+VvS36Wn+VvS36Wn+VvS36Wn+VvS36Wn+VAAAAAAAAAAAAAAAAvbPb/wF4AAAD/
/2TsM/QAAAD9SURBVHja7cEBAQAAAIIg/69uSEAAAAAAAAAAAAAAAACAbwNdAAEBxggAAAAASUVO
RK5CYII=" | base64 -d > "$MANIFEST_DIR/color.png" 2>/dev/null || \
    echo "Warning: Could not create placeholder icon. Please provide your own color.png (192x192)"
fi

if [ ! -f "$MANIFEST_DIR/outline.png" ]; then
    echo "Creating placeholder: outline.png (32x32)"
    echo "iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAMAAABEpIrGAAAABGdBTUEAALGPC/xhBQAAAAFzUkdC
AK7OHOkAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAAYdEVYdFNvZnR3YXJlAHBhaW50Lm5ldCA0LjEu
NWRHWFIAAAAMUExURUdwTP///wAAAP///5E/6jwAAAAEdFJOUwBAgL/vGTsyAAAAO0lEQVQ4y2Ng
GAVDBDAyMTExoQswMTEBedgEmJmZGdAFmJmZwWLoApgEMAUYBRgFGAUYBUYBRsqCAQD0tAEKKJp0
NQAAAABJRU5ErkJggg==" | base64 -d > "$MANIFEST_DIR/outline.png" 2>/dev/null || \
    echo "Warning: Could not create placeholder icon. Please provide your own outline.png (32x32)"
fi

# Create the zip file
echo ""
echo "Creating Teams app package..."
cd "$MANIFEST_DIR"

# Files to include in the zip (bot manifest only)
ZIP_FILES="manifest.json color.png outline.png"

# Create zip with agent name in filename (sanitize name for filename)
ZIP_NAME=$(echo "$AGENT_NAME" | tr ' ' '-' | tr -cd 'a-zA-Z0-9-_')
rm -f "${ZIP_NAME}.zip"

OUTPUT_FILENAME="${ZIP_NAME}.zip"
if command -v zip &> /dev/null; then
    zip -q "$OUTPUT_FILENAME" $ZIP_FILES
else
    # Fallback to Python for Windows/environments without zip
    # Use relative path since we're already in MANIFEST_DIR
    python3 -c "
import zipfile
files = '$ZIP_FILES'.split()
with zipfile.ZipFile('$OUTPUT_FILENAME', 'w', zipfile.ZIP_DEFLATED) as z:
    for f in files:
        z.write(f)
" 2>/dev/null || python -c "
import zipfile
files = '$ZIP_FILES'.split()
with zipfile.ZipFile('$OUTPUT_FILENAME', 'w', zipfile.ZIP_DEFLATED) as z:
    for f in files:
        z.write(f)
"
fi
cd "$PROJECT_ROOT"

echo ""
echo "=========================================="
echo "✅ Teams App Package Created!"
echo "=========================================="
echo ""
echo "Package: teams-manifest/${ZIP_NAME}.zip"
echo ""
echo "Files included:"
for f in $ZIP_FILES; do
    echo "  - $f"
done
echo ""
echo "Next Steps:"
echo ""
echo "1. (Optional) Replace placeholder icons with your own:"
echo "   - teams-manifest/color.png: 192x192 full color icon"
echo "   - teams-manifest/outline.png: 32x32 transparent outline icon"
echo "   Then re-run this script to update the zip."
echo ""
echo "2. Upload to Teams:"
echo "   Option A - Sideload (for testing):"
echo "     - Open Teams → Apps → Manage your apps → Upload an app"
echo "     - Select 'onedrive-agent-teams.zip'"
echo ""
echo "   Option B - Organization catalog:"
echo "     - Go to Teams Admin Center → Teams apps → Manage apps"
echo "     - Click 'Upload new app' → Select the zip"
echo "     - Approve the app for your organization"
echo ""
echo "3. Ensure SSO is configured (from 01-admin-create-apps.sh):"
echo "   - Identifier URI: api://botid-$BOT_APP_ID"
echo "   - Teams clients pre-authorized"
echo ""
