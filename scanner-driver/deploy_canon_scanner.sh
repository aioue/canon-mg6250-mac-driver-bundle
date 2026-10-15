#!/bin/bash
# ==============================================================================
# Script: deploy_canon_scanner.sh
# Description: Extracts and deploys the legacy Canon MG6200 series scanner driver
#              (ICA module + BJNP plugin + legacy network registration helper).
# Usage: ./deploy_canon_scanner.sh [--headless-scan]
#        Place 'misd-mac-ijscanner1-4_0_0-ea19_2.dmg' in the same directory.
#        Requires sudo privileges.
#        --headless-scan: after the driver install, install the headless scan
#        script and a per-user LaunchAgent that runs CIJScannerRegister at
#        login. The agent publishes the registered ICA device entry that
#        scripted scans must be driven through; without it the entry is
#        missing after a reboot. Optional — omit for USB-only use.
# Tested: macOS Tahoe 26.x (Apple Silicon)
# Note: Will work until Rosetta 2 translation layer is no longer shipped with macOS.
# Note: This is an unsupported "side-load" of x86_64 Canon binaries (Rosetta).
# ==============================================================================

set -euo pipefail

NETWORK=0
if [[ "${1:-}" == "--headless-scan" ]]; then
  NETWORK=1
elif [[ $# -gt 0 ]]; then
  echo "Error: unknown argument '$1' (usage: $0 [--headless-scan])" >&2
  exit 1
fi

DMG="misd-mac-ijscanner1-4_0_0-ea19_2.dmg"
WORKDIR="$(pwd)/scanner_extraction_work"
DEST_ICA="/Library/Image Capture/Devices"
DEST_REGISTER="/Library/Image Capture/Support/LegacyDeviceDiscoveryHelpers"
DEST_PLUG="/Library/Printers/Canon/IJScanner/Plugins"

if [[ ! -f "$DMG" ]]; then
  echo "Error: $DMG not found in current directory." >&2
  exit 1
fi

echo "--- Mounting DMG ---"
PLIST_OUT=$(mktemp)
hdiutil attach -plist -nobrowse "$DMG" >"$PLIST_OUT"
VOLUME=""
for i in $(seq 0 20); do
  mp=$(plutil -extract "system-entities.${i}.mount-point" raw "$PLIST_OUT" 2>/dev/null) || true
  [[ -n "$mp" && -d "$mp" ]] || continue
  VOLUME="$mp"
  break
done
rm -f "$PLIST_OUT"
if [[ -z "$VOLUME" ]]; then
  echo "Error: could not determine DMG mount point." >&2
  exit 1
fi

OUTER_PKG=$(find "$VOLUME" -maxdepth 1 -name '*.pkg' ! -name '.*' 2>/dev/null | head -1)
if [[ -z "$OUTER_PKG" ]]; then
  echo "Error: no .pkg at root of DMG volume." >&2
  hdiutil detach "$VOLUME" 2>/dev/null || true
  exit 1
fi

echo "--- Expanding packages (outer: $(basename "$OUTER_PKG")) ---"
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR/outer" "$WORKDIR/payload"
pkgutil --expand "$OUTER_PKG" "$WORKDIR/outer"

INNER_PKG_DIR=$(find "$WORKDIR/outer" -name '*.pkg' -type d 2>/dev/null | head -1)
if [[ -z "$INNER_PKG_DIR" || ! -f "$INNER_PKG_DIR/Payload" ]]; then
  echo "Error: inner package Payload not found after expand." >&2
  hdiutil detach "$VOLUME" 2>/dev/null || true
  exit 1
fi

echo "--- Extracting cpio Payload ---"
( cd "$WORKDIR/payload" && gzip -dc "$INNER_PKG_DIR/Payload" | cpio -idm )

SRC_APP="$WORKDIR/payload/Library/Image Capture/Devices/Canon IJScanner1.app"
SRC_REGISTER="$WORKDIR/payload/Library/Image Capture/Support/LegacyDeviceDiscoveryHelpers/CIJScannerRegister.app"
SRC_PLUG_DIR="$WORKDIR/payload/Library/Printers/Canon/IJScanner/Plugins"

if [[ ! -d "$SRC_APP" ]]; then
  echo "Error: missing $SRC_APP in payload." >&2
  hdiutil detach "$VOLUME" 2>/dev/null || true
  exit 1
fi

echo "--- Deploying files ---"
sudo mkdir -p "$DEST_ICA" "$DEST_REGISTER" "$DEST_PLUG"

sudo cp -R "$SRC_APP" "$DEST_ICA/"
if [[ -d "$SRC_REGISTER" ]]; then
  sudo cp -R "$SRC_REGISTER" "$DEST_REGISTER/"
fi
if [[ -d "$SRC_PLUG_DIR" ]]; then
  sudo cp -R "$SRC_PLUG_DIR/"*.plugin "$DEST_PLUG/"
fi

echo "--- Applying permissions and ad-hoc signatures ---"
sudo xattr -cr "$DEST_ICA/Canon IJScanner1.app"
sudo codesign --force --deep --sign - "$DEST_ICA/Canon IJScanner1.app"

if [[ -d "$DEST_REGISTER/CIJScannerRegister.app" ]]; then
  sudo xattr -cr "$DEST_REGISTER/CIJScannerRegister.app"
  sudo codesign --force --deep --sign - "$DEST_REGISTER/CIJScannerRegister.app"
fi

for f in "$DEST_PLUG"/*.plugin; do
  [[ -e "$f" ]] || continue
  sudo xattr -cr "$f"
  sudo codesign --force --deep --sign - "$f"
done

echo "--- Cleanup and discovery reload ---"
hdiutil detach "$VOLUME"
sudo killall ImageCaptureServices 2>/dev/null || true

if [[ "$NETWORK" -eq 1 ]]; then
  echo "--- Headless scan setup (--headless-scan) ---"
  # CIJScannerRegister publishes the registered ICA device entry that network
  # scans must be driven through (the Bonjour entry fails -9933). Without the
  # agent it only starts when something else launches it, and a reboot leaves
  # network scanning broken.
  AGENT_DIR="$HOME/Library/LaunchAgents"
  AGENT_PLIST="$AGENT_DIR/jp.co.canon.CIJScannerRegister.plist"
  mkdir -p "$AGENT_DIR"
  cat > "$AGENT_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>jp.co.canon.CIJScannerRegister</string>
  <key>ProgramArguments</key><array>
    <string>$DEST_REGISTER/CIJScannerRegister.app/Contents/MacOS/CIJScannerRegister</string>
  </array>
  <key>RunAtLoad</key><true/>
</dict></plist>
PLIST
  launchctl bootout gui/"$(id -u)/jp.co.canon.CIJScannerRegister" 2>/dev/null || true
  launchctl bootstrap gui/"$(id -u)" "$AGENT_PLIST"
  # Headless scan script next to the verify script for terminal use.
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [[ -f "$SCRIPT_DIR/scan_network_test.swift" ]]; then
    sudo mkdir -p /usr/local/bin
    sudo install -m 755 "$SCRIPT_DIR/scan_network_test.swift" /usr/local/bin/canon-scan-test.swift
  fi
fi

echo "--- Deployment complete ---"
echo ""
echo "Canon ICA module name is 'Canon IJScanner1.app' (the '1' is Canon's product name, not a duplicate install)."
echo ""
echo "Network scanning (Wi-Fi/Ethernet):"
echo "  1. Run: ./verify_network_scan.sh"
echo "  2. GUI note: the 'Shared' (Bonjour) entry fails -9933 on this printer —"
echo "     headless scanning via the registered entry is the proven path."
echo "  3. For headless scanning, deploy with --headless-scan and run:"
echo "     swift /usr/local/bin/canon-scan-test.swift"
echo "     (requires Image Capture GUI closed; scans the registered ICA entry)"
echo ""
echo "USB scanning:"
echo "  1. Plug in USB, wait a few seconds."
echo "  2. Open Image Capture → device under 'Devices'."
echo ""
echo "If a network scan fails with -9933 ('cannot communicate'): quit Image"
echo "Capture (the Canon module services one client), and scan the registered"
echo "ICA entry — see README 'Network scanning' for the working procedure."
echo ""
echo "Debug: /usr/bin/log stream --predicate 'process == \"Canon IJScanner1\" OR process == \"Image Capture\"'"
