#!/bin/bash
# ==============================================================================
# Script: deploy_printer_driver.sh
# Description: Side-load Canon MG6200 filters/scanner from DMGs (no .pkg install).
# Usage: ./deploy_printer_driver.sh
# DMGs are expected next to this script (see README.md in the repository root). Printer DMG is required;
# scanner DMG is optional — place misd-mac-ijscanner1-*.dmg here if you use it.
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
P_DMG="${P_DMG:-$SCRIPT_DIR/mcpd-mac-mg6200-16_20_0_0-ea21_3.dmg}"
S_DMG="${S_DMG:-$SCRIPT_DIR/misd-mac-ijscanner1-4_0_0-ea19_2.dmg}"
WORK_DIR="${WORK_DIR:-$SCRIPT_DIR/canon_tmp/driver_legacy}"
SCAN_DEST="/Library/Image Capture/Devices"
PRINT_DEST="/Library/Printers/Canon/BJPrinter"
PPD="/etc/cups/ppd/Canon_MG6250_Test.ppd"

# 1. Cleanup and Setup
sudo rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

# 2. Extract and Deploy Scanner (optional second DMG)
if [[ -f "$S_DMG" ]]; then
  echo "Deploying Scanner..."
  S_VOL=$(hdiutil attach -nobrowse "$S_DMG" | awk -F'\t' '/Apple_HFS|Apple_APFS/ {print $3}')
  pkgutil --expand "$S_VOL/"*.pkg "$WORK_DIR/scanner"
  sudo mkdir -p "$SCAN_DEST"
  sudo cp -R "$WORK_DIR/scanner/Library/Image Capture/Devices/Canon IJScanner1.app" "$SCAN_DEST/"
  sudo xattr -cr "$SCAN_DEST/Canon IJScanner1.app"
  sudo codesign --force --deep --sign - "$SCAN_DEST/Canon IJScanner1.app"
  hdiutil detach "$S_VOL"
else
  echo "Skipping scanner (not found: $S_DMG)"
fi

# 3. Extract and Deploy Printer Filters
echo "Deploying Printer..."
P_VOL=$(hdiutil attach -nobrowse "$P_DMG" | awk -F'\t' '/Apple_HFS|Apple_APFS/ {print $3}')
pkgutil --expand "$P_VOL/"*.pkg "$WORK_DIR/printer"
sudo mkdir -p "$PRINT_DEST"
sudo cp -R "$WORK_DIR/printer/Library/Printers/Canon/BJPrinter/Filters" "$PRINT_DEST/"
sudo xattr -cr "$PRINT_DEST/Filters"
sudo codesign --force --deep --sign - "$PRINT_DEST/Filters"
hdiutil detach "$P_VOL"

# 4. Optional: register Raster2CanonIJ for cups-raster (experimental on modern macOS)
# Do NOT remove existing *cupsFilter lines (AirPrint URF/JPEG). Raster2CanonIJ + Apple's
# cgpdftoraster often fails with "No pages found!" — restore from .bak if printing breaks.
FILTER_PATH="/Library/Printers/Canon/BJPrinter/Filters/Raster2CanonIJ/Raster2CanonIJ.bundle/Contents/MacOS/Raster2CanonIJ"
if [ -f "$PPD" ] && ! grep -q 'Raster2CanonIJ' "$PPD"; then
    echo "Appending cups-raster filter to PPD (keeping existing AirPrint filters)..."
    sudo cp "$PPD" "$PPD.bak"
    echo "*cupsFilter: \"application/vnd.cups-raster 100 $FILTER_PATH\"" | sudo tee -a "$PPD"
fi

# 5. Cleanup
sudo killall cupsd ImageCaptureServices
rm -rf "$WORK_DIR"

echo "Deployment complete."
