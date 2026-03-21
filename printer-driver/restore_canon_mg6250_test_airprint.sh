#!/bin/bash
# Restore Canon_MG6250_Test PPD from backup created before Raster2CanonIJ was appended.
# Run when the test queue fails with "No pages found!" or filter errors.
set -euo pipefail
PPD="/etc/cups/ppd/Canon_MG6250_Test.ppd"
BAK="${PPD}.bak"
if [[ ! -f "$BAK" ]]; then
  echo "Missing $BAK — nothing to restore." >&2
  exit 1
fi
sudo cp "$BAK" "$PPD"
sudo killall cupsd 2>/dev/null || true
echo "Restored $PPD from backup. Try printing again."
