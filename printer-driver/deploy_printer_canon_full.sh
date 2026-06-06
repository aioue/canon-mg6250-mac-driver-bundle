#!/bin/bash
# ==============================================================================
# deploy_printer_canon_full.sh
# Side-load full Canon MG6200 BJPrinter tree (Frameworks + Filters + Resources)
# and install the official gzipped PPD from CanonIJPPD.tgz.
#
# Flat pkgutil --expand does NOT unpack the cpio Payload; this script extracts it.
# Usage: ./deploy_printer_canon_full.sh
# DRY_RUN=1 ./deploy_printer_canon_full.sh  — extract only (no sudo copy).
# Requires: sudo (unless DRY_RUN=1), DMG at P_DMG (same as deploy_printer_driver.sh).
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
P_DMG="${P_DMG:-$SCRIPT_DIR/mcpd-mac-mg6200-16_20_0_0-ea21_3.dmg}"
WORK_PARENT="$SCRIPT_DIR/canon_tmp"
# Use a fresh directory each run: cpio payloads may contain root-owned modes; reusing one path can make rm -rf fail.
WORK_DIR="${WORK_DIR:-$(mkdir -p "$WORK_PARENT" && mktemp -d "${WORK_PARENT}/full_deploy.XXXXXX")}"
PRINT_DEST="/Library/Printers/Canon/BJPrinter"
PPD_DIR="/Library/Printers/PPDs/Contents/Resources"
PPD_GZ_NAME="CanonIJMG6200series.ppd.gz"
DRY_RUN="${DRY_RUN:-0}"
SUDO="${SUDO:-sudo}"

if [[ ! -f "$P_DMG" ]]; then
  echo "ERROR: Printer DMG not found: $P_DMG" >&2
  exit 1
fi

mkdir -p "$WORK_DIR/local_pkg" "$WORK_DIR/flat" "$WORK_DIR/payload"

echo "Mounting printer DMG..."
# Prefer plist output: text hdiutil lines vary (HFS vs APFS slice labels); empty P_VOL caused "got: none".
PLIST_OUT=$(mktemp)
hdiutil attach -plist -nobrowse "$P_DMG" >"$PLIST_OUT"
P_VOL=""
for i in $(seq 0 20); do
  mp=$(plutil -extract "system-entities.${i}.mount-point" raw "$PLIST_OUT" 2>/dev/null) || true
  [[ -n "$mp" && -d "$mp" ]] || continue
  P_VOL="$mp"
  break
done
rm -f "$PLIST_OUT"

if [[ -z "$P_VOL" ]]; then
  echo "ERROR: Could not read mount-point from hdiutil -plist (DMG mounted but path unknown). Detach manually in Disk Utility if needed." >&2
  exit 1
fi

PKG_FILE=$(find "$P_VOL" -maxdepth 1 -name '*.pkg' ! -name '.*' 2>/dev/null | head -1)
PKG_COUNT=$(find "$P_VOL" -maxdepth 1 -name '*.pkg' ! -name '.*' 2>/dev/null | wc -l | tr -d ' ')
if [[ -z "$PKG_FILE" || "$PKG_COUNT" != "1" ]]; then
  echo "ERROR: Expected exactly one .pkg at root of \"$P_VOL\", found: ${PKG_COUNT:-0}" >&2
  ls -la "$P_VOL" 2>&1 | sed 's/^/  /' >&2 || true
  hdiutil detach "$P_VOL" 2>/dev/null || true
  exit 1
fi

cp "$PKG_FILE" "$WORK_DIR/local_pkg/MG6200_flat.pkg"
hdiutil detach "$P_VOL" || true

echo "Expanding package metadata..."
pkgutil --expand "$WORK_DIR/local_pkg/MG6200_flat.pkg" "$WORK_DIR/flat/printer"
MG_PKG="$WORK_DIR/flat/printer/MG6200.pkg"
if [[ ! -f "$MG_PKG/Payload" ]]; then
  echo "ERROR: Missing MG6200.pkg/Payload under expanded pkg" >&2
  exit 1
fi

echo "Extracting cpio Payload (this is the full driver tree)..."
( cd "$WORK_DIR/payload" && gzip -dc "$MG_PKG/Payload" | cpio -idm )

SRC_ROOT="$WORK_DIR/payload/Library/Printers/Canon/BJPrinter"
if [[ ! -d "$SRC_ROOT/Filters" ]]; then
  echo "ERROR: Payload missing $SRC_ROOT/Filters" >&2
  exit 1
fi

echo "Installing official PPD from Scripts tarball..."
tar zxfp "$MG_PKG/Scripts/CIJModules/CanonIJPPD.tgz" -C "$WORK_DIR"
if [[ ! -f "$WORK_DIR/$PPD_GZ_NAME" ]]; then
  echo "ERROR: CanonIJPPD.tgz did not contain $PPD_GZ_NAME" >&2
  exit 1
fi

if [[ "$DRY_RUN" == "1" ]]; then
  echo "DRY_RUN=1: payload ready at $SRC_ROOT — skipping sudo copy."
  echo "Inspect filters: ls -la \"$SRC_ROOT/Filters\""
  echo "Official PPD:  $WORK_DIR/$PPD_GZ_NAME"
  echo "Remove when done: rm -rf \"$WORK_DIR\""
  exit 0
fi

echo "Copying to $PRINT_DEST ($SUDO)..."
$SUDO mkdir -p "$PRINT_DEST" "$PPD_DIR"
for sub in Frameworks Filters Resources; do
  if [[ -d "$SRC_ROOT/$sub" ]]; then
    echo "  -> $sub"
    $SUDO rm -rf "$PRINT_DEST/$sub"
    $SUDO cp -R "$SRC_ROOT/$sub" "$PRINT_DEST/"
    $SUDO xattr -cr "$PRINT_DEST/$sub"
    $SUDO codesign --force --deep --sign - "$PRINT_DEST/$sub" 2>/dev/null || true
  fi
done

echo "  -> $PPD_DIR/$PPD_GZ_NAME"
$SUDO cp "$WORK_DIR/$PPD_GZ_NAME" "$PPD_DIR/$PPD_GZ_NAME"
$SUDO chmod 644 "$PPD_DIR/$PPD_GZ_NAME"

echo "Restarting CUPS..."
$SUDO killall cupsd 2>/dev/null || true

rm -rf "$WORK_DIR"

echo "Done. Full BJPrinter subtrees + official PPD installed."
echo "Next: ./add_canon_mg6250_official_queue.sh [source_queue]"
echo "      (default source_queue: Canon_MG6250_Test — URI is copied for the new queue)"
