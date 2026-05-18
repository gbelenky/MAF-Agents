# Teams Manifest Output

This folder contains generated Teams app manifest packages.

Files created by `scripts/03-teams-manifest.sh`:
- `manifest.json` - Generated manifest with substituted values
- `color.png` - App color icon (192x192)
- `outline.png` - App outline icon (32x32)
- `<BotName>.zip` - Complete package for Teams upload

## Upload to Teams

**Option A: Teams Admin Center**
1. Go to https://admin.teams.microsoft.com
2. Navigate to Teams apps > Manage apps
3. Click "Upload new app"
4. Select the .zip file

**Option B: Sideload in Teams**
1. Open Teams
2. Go to Apps > Manage your apps
3. Click "Upload an app" > "Upload a custom app"
4. Select the .zip file
