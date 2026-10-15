#!/bin/bash
# ==============================================================================
# verify_network_scan.sh — quick mDNS / BJNP checks (bounded runtime, no sudo).
# Run from scanner-driver/ after the printer is on and on the same LAN.
# ==============================================================================

set -euo pipefail

BROWSE_SEC="${BROWSE_SEC:-12}"
HOST_GUESS="${HOST_GUESS:-Canon-MG6250.local}"

run_bounded() {
  local sec="$1"
  shift
  perl -e 'alarm shift; exec @ARGV' -- "$sec" "$@"
}

echo "=== mDNS: _scanner._tcp (Canon BJNP scan service) ==="
echo "(Browsing ${BROWSE_SEC}s — same family of discovery as AirPrint, different service name.)"
run_bounded "$BROWSE_SEC" dns-sd -B _scanner._tcp local. 2>/dev/null | tee /tmp/canon-verify-scanner-mdns.txt | grep -i -E 'canon|mg62|ADD|can be reached' || true
if ! grep -qi canon /tmp/canon-verify-scanner-mdns.txt 2>/dev/null; then
  echo "WARN: no Canon _scanner._tcp seen. Check printer power, Wi-Fi, and same subnet/multicast."
fi

echo ""
echo "=== mDNS: _ipp._tcp (print) ==="
run_bounded 8 dns-sd -B _ipp._tcp local. 2>/dev/null | grep -i -E 'canon|mg62|ADD' | head -5 || true

echo ""
echo "=== Ping hostname (optional) ==="
ping -c 1 -W 2 "$HOST_GUESS" 2>/dev/null || echo "ping failed for $HOST_GUESS (may still work via mDNS in apps)"

echo ""
echo "=== UDP BJNP port 8612 (quick probe) ==="
IP=$(ping -c 1 -W 2 "$HOST_GUESS" 2>/dev/null | sed -n 's/.*(\([0-9.]*\)).*/\1/p' | head -1)
if [[ -n "$IP" ]]; then
  if printf 'BJNP' | nc -u -G 2 -w 2 "$IP" 8612 2>/dev/null | xxd | head -1; then
    echo "BJNP reply from $IP:8612 (UDP) — scanner service is reachable."
  else
    echo "No UDP reply on $IP:8612 (printer may still work via ICA; try Image Capture)."
  fi
  echo "Note: TCP connect to 8612 often fails; BJNP uses UDP on this model."
else
  echo "Skip UDP probe (no IP)."
fi

echo ""
echo "Done. For headless network scan: swift scan_network_test.swift (registered"
echo "entry; requires Image Capture closed)."
