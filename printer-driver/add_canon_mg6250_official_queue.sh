#!/bin/bash
# ==============================================================================
# add_canon_mg6250_official_queue.sh
# Create a CUPS queue using the Canon-supplied PPD (CanonIJMG6200series.ppd.gz).
#
# Usage (pick one):
#   ./add_canon_mg6250_official_queue.sh [SOURCE_QUEUE] [NEW_QUEUE] [DISPLAY_NAME]
#       Reuse device URI from an existing queue. Optional DISPLAY_NAME sets lpadmin -D
#       (shown in Print dialog). Defaults: SOURCE_QUEUE=Canon_MG6250_Test,
#       NEW_QUEUE=Canon_MG6250_CanonPPD
#
#   ./add_canon_mg6250_official_queue.sh 'ipp://...'|'dnssd://...' [NEW_QUEUE] [DISPLAY_NAME]
#       Pass the printer URI directly. NEW_QUEUE must be CUPS-safe: letters, digits,
#       hyphen, underscore, dot only (no spaces or parentheses — lpadmin rejects them).
#
# lpadmin queue names are case-sensitive.
# ==============================================================================

set -euo pipefail

NEW_QUEUE_DEFAULT="Canon_MG6250_CanonPPD"
PPD_GZ="/Library/Printers/PPDs/Contents/Resources/CanonIJMG6200series.ppd.gz"

if [[ ! -f "$PPD_GZ" ]]; then
  echo "ERROR: Missing $PPD_GZ — run ./deploy_printer_canon_full.sh first." >&2
  exit 1
fi

DISPLAY_NAME=""
if [[ "${1:-}" == *"://"* ]]; then
  URI="$1"
  NEW_QUEUE="${2:-$NEW_QUEUE_DEFAULT}"
  DISPLAY_NAME="${3:-}"
else
  SOURCE_QUEUE="${1:-Canon_MG6250_Test}"
  NEW_QUEUE="${2:-$NEW_QUEUE_DEFAULT}"
  DISPLAY_NAME="${3:-}"
  if ! lpstat -p "$SOURCE_QUEUE" &>/dev/null; then
    echo "ERROR: Source queue '$SOURCE_QUEUE' not found. Printers:" >&2
    lpstat -p 2>&1 | head -20 >&2
    echo "" >&2
    echo "Add the printer once in System Settings (AirPrint/Bonjour), or pass a URI:" >&2
    echo "  $0 'dnssd://YourPrinter._ipp._tcp.local./?uuid=...' $NEW_QUEUE_DEFAULT" >&2
    exit 1
  fi
  URI=$(lpstat -v "$SOURCE_QUEUE" 2>/dev/null | sed -n 's/^device for .*: //p')
fi

if [[ -z "$URI" ]]; then
  echo "ERROR: Empty device URI." >&2
  exit 1
fi

echo "Device URI:   $URI"
echo "Queue name:   $NEW_QUEUE"
[[ -n "$DISPLAY_NAME" ]] && echo "Display name: $DISPLAY_NAME (lpadmin -D)"
echo "PPD:          $PPD_GZ"

if lpstat -p "$NEW_QUEUE" &>/dev/null; then
  echo "Removing existing queue $NEW_QUEUE..."
  sudo lpadmin -x "$NEW_QUEUE"
fi

LPADMIN_ARGS=( -p "$NEW_QUEUE" -E -v "$URI" -P "$PPD_GZ" )
[[ -n "$DISPLAY_NAME" ]] && LPADMIN_ARGS+=( -D "$DISPLAY_NAME" )

sudo lpadmin "${LPADMIN_ARGS[@]}"
sudo killall cupsd 2>/dev/null || true

echo "Queue $NEW_QUEUE created. Test with: lp -d $NEW_QUEUE /path/to/file.pdf"
