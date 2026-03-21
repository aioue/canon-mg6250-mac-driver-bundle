#!/bin/bash
# ==============================================================================
# install_canon_mg6250_bonjour_network.sh
# One-shot: enable CUPS debug logging, deploy Canon driver from this folder's DMG,
# add a Bonjour/IPP queue using ippfind, show a short log excerpt, then turn debug off.
#
# CUPS queue IDs cannot contain spaces or parentheses; we use a safe ID and set the
# human-readable name via lpadmin -D (appears in the Print dialog).
#
# Run from this directory:  ./install_canon_mg6250_bonjour_network.sh
# Requires: sudo, printer on network, ippfind sees the printer.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# lpadmin -p name: [A-Za-z0-9._-] only (no spaces, no parens)
QUEUE_ID='Canon-MG6250-Bonjour-Network'
# Shown as printer title in macOS Print dialog
QUEUE_DISPLAY='Canon-MG6250 (Bonjour Network)'

cleanup_debug() {
  echo ""
  echo "Turning off CUPS debug logging (cleanup)..."
  sudo cupsctl --no-debug-logging 2>/dev/null || true
}
trap cleanup_debug EXIT

echo "Discovering IPP printer (Bonjour / _ipp._tcp)..."
IPP_URI=$(ippfind -T 8 2>/dev/null | grep -i -m1 -E 'canon|mg6250|mg6200' || true)
if [[ -z "$IPP_URI" ]]; then
  IPP_URI=$(ippfind -T 8 2>/dev/null | head -1 || true)
fi
if [[ -z "$IPP_URI" ]]; then
  echo "ERROR: ippfind found no printers. Power on the printer and ensure Wi-Fi/Ethernet works." >&2
  exit 1
fi

echo "Using device URI: $IPP_URI"
echo "Queue ID (-p):    $QUEUE_ID"
echo "Display name:     $QUEUE_DISPLAY"
echo ""

echo "Enabling CUPS debug logging..."
sudo cupsctl --debug-logging

./deploy_printer_canon_full.sh

./add_canon_mg6250_official_queue.sh "$IPP_URI" "$QUEUE_ID" "$QUEUE_DISPLAY"

echo ""
echo "=== Queue status ==="
lpstat -p "$QUEUE_ID" 2>&1 || true
lpstat -v "$QUEUE_ID" 2>&1 || true

echo ""
echo "=== Recent CUPS lines (queue / Raster2Canon / lpadmin) ==="
grep -E 'Canon-MG6250|Bonjour|lpadmin|Raster2CanonIJ|cgpdftoraster|CUPS-Add-Modify|Printer drivers are deprecated' /var/log/cups/error_log 2>/dev/null | tail -60 || true

echo ""
echo "Disabling CUPS debug logging..."
sudo cupsctl --no-debug-logging
trap - EXIT

echo ""
echo "Done. Debug logging is OFF."
echo "Test print: lp -d $QUEUE_ID /path/to/file.pdf"
echo "In Print dialog, look for display name: $QUEUE_DISPLAY (queue ID: $QUEUE_ID)"
