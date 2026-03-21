#!/bin/bash
# ==============================================================================
# Script: deploy_canon_scanner.sh
# Description: Extracts and deploys the legacy Canon MG6200 series scanner driver.
# Usage: ./deploy_canon_scanner.sh
#        Place 'misd-mac-ijscanner1-4_0_0-ea19_2.dmg' in the same directory.
#        Requires sudo privileges.
# Tested: macOS Tahoe 26.3 (Apple Silicon)
# Note: Will work until Rosetta 2 translation layer is no longer shipped with OSX.
# Note: This is an unsupported "side-load" of 64-bit binaries.
# ==============================================================================

DMG="misd-mac-ijscanner1-4_0_0-ea19_2.dmg"
PKG="canonijscanner1.pkg"
WORKDIR="$(pwd)/scanner_extraction_work"
DEST_ICA="/Library/Image Capture/Devices"
DEST_PLUG="/Library/Printers/Canon/IJScanner/Plugins"

if [ ! -f "$DMG" ]; then
    echo "Error: $DMG not found in current directory."
    exit 1
fi

echo "--- Mounting DMG ---"
VOLUME=$(hdiutil attach -nobrowse "$DMG" | grep /Volumes | awk '{print $3}')

echo "--- Extracting Payload ---"
mkdir -p "$WORKDIR"
# Expanding nested package structure
pkgutil --expand "$VOLUME/$PKG" "$WORKDIR/extracted"

echo "--- Deploying Files ---"
# Create directories (Idempotent)
sudo mkdir -p "$DEST_ICA" "$DEST_PLUG"

# Move Scanner Application
sudo cp -R "$WORKDIR/extracted/Library/Image Capture/Devices/Canon IJScanner1.app" "$DEST_ICA/"

# Move Plugins
sudo cp -R "$WORKDIR/extracted/Library/Printers/Canon/IJScanner/Plugins/"*.plugin "$DEST_PLUG/"

echo "--- Applying Permissions and Signatures ---"
# Remove Quarantine and re-sign for Apple Silicon execution
sudo xattr -cr "$DEST_ICA/Canon IJScanner1.app"
sudo codesign --force --deep --sign - "$DEST_ICA/Canon IJScanner1.app"

for f in "$DEST_PLUG"/*.plugin; do
    sudo xattr -cr "$f"
    sudo codesign --force --deep --sign - "$f"
done

echo "--- Cleanup and Discovery ---"
# Detach DMG
hdiutil detach "$VOLUME"
# Force reload of ICA services
sudo killall ImageCaptureServices

echo "--- Deployment Complete ---"
echo "1. IMPORTANT: Unplug your USB scanner, wait 5 seconds, and replug it."
echo "2. Launch 'Image Capture' to test."
echo "3. To debug, run this command in a terminal while opening Image Capture:"
echo "log stream --predicate 'subsystem == \"com.apple.ImageCaptureCore\"'"