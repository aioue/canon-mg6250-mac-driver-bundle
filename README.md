# Canon PIXMA MG6250 - macOS printer and scanner install kit

Unofficial scripts to install **Canon PIXMA MG6250** (MG6200-series) **printing** and **scanning** on **current macOS** using Canon’s **last official Mac drivers** - the **macOS 10.13 (High Sierra)** builds from Canon’s support site:

[Canon Europe - PIXMA MG6250 drivers (macOS 10.13)](https://www.canon-europe.com/support/consumer/products/printers/pixma/mg-series/pixma-mg6250.html?type=drivers&language=EN&os=macOS%2010.13%20(High%20Sierra))

**This project is not affiliated with or endorsed by Canon.**

## Testing and feedback

This has **only been tested on the maintainer’s setup** (including **macOS Tahoe 26.3** on **Apple Silicon** for the scanner path). Your mileage may vary. **Bug reports and pull requests are welcome.**

## What’s in this repository

| Path | Role |
|------|------|
| [`scanner-driver/`](scanner-driver/) | IJ Scanner install (`deploy_canon_scanner.sh`), [`verify_network_scan.sh`](scanner-driver/verify_network_scan.sh), headless [`scan_network_test.swift`](scanner-driver/scan_network_test.swift), Canon scanner DMG |
| [`printer-driver/`](printer-driver/) | CUPS / IJ printer install scripts and Canon printer DMG |

Canon’s **official disk images** are **included in this repository** under those folders (see [`CANON_DMG_NOTICE.md`](CANON_DMG_NOTICE.md) - they are **Canon’s software**, not covered by this repo’s MIT license). If your copy omits them, download the same files from Canon using the link above.

## Prerequisites

- **macOS** (these scripts use `hdiutil`, `pkgutil`, `codesign`, CUPS).
- **`sudo`** for installing under `/Library`.
- **Apple Silicon:** printer filters are **x86_64** - install **Rosetta 2** if prompted.
- **Network printing:** the recommended printer flow discovers the device via Bonjour/IPP (`ippfind`).

## Quick start - scanner

After clone, the scanner DMG should be at `scanner-driver/misd-mac-ijscanner1-4_0_0-ea19_2.dmg` (same file Canon ships for High Sierra).

```bash
cd /path/to/canon-mg6250-mac-driver-bundle/scanner-driver
chmod +x deploy_canon_scanner.sh verify_network_scan.sh
./deploy_canon_scanner.sh              # USB-only scanning
# or:
./deploy_canon_scanner.sh --headless-scan
                                       # also installs the headless scan script
                                       # to /usr/local/bin and a per-user
                                       # LaunchAgent that runs CIJScannerRegister
                                       # at login, keeping the registered ICA
                                       # scan entry alive across reboots
./verify_network_scan.sh
```

Then open **Image Capture**:

- **USB scan:** pick the Canon under **Devices** (plug in USB first).
- **Network scan:** headless via `scan_network_test.swift` is the proven path (drives the **registered** ICA entry — see [Network scanning](#network-scanning-mdns-and-image-capture)). The GUI "Shared"/Bonjour entry fails −9933 on this printer.

**Name `Canon IJScanner1.app`:** the trailing **`1`** is Canon’s ICA product name (`ijscanner1` in the DMG filename). It is not a second copy you installed by mistake, and you should not rename it.

To debug: `/usr/bin/log stream --predicate 'process == "Canon IJScanner1" OR process == "Image Capture"'` (use `/usr/bin/log` over SSH — plain `log` is a zsh builtin).

## Network scanning (mDNS and Image Capture)

The full write-up of what makes network scanning work (and why the Bonjour entry fails -9933) is in [`scanner-driver/network-scanning.md`](scanner-driver/network-scanning.md).

The MG6250 does **not** advertise Apple’s driverless scan services (`_uscan._tcp` / `_airscan._tcp`). Network scan uses Canon’s **BJNP** stack over **mDNS** (multicast DNS, the same discovery family Bonjour uses for printing).

| What you might know | What the MG6250 uses |
|---------------------|----------------------|
| AirPrint printer discovery | `_ipp._tcp` on port 631 |
| “AirScan” / driverless scan | `_uscan._tcp` — **not** on this printer |
| Canon network scan | **`_scanner._tcp`** on **UDP port 8612** (BJNP) |

**mDNS in one minute:** your Mac sends a multicast question on the LAN (“who provides `_scanner._tcp`?”). The printer answers with a hostname such as `Canon-MG6250.local` and port **8612**. No static IP is required, but the Mac and printer must be on the **same subnet** with **multicast allowed** (typical home Wi‑Fi is fine; some guest VLANs block it).

**Check discovery (no sudo):**

```bash
cd scanner-driver
./verify_network_scan.sh
# or manually (Ctrl+C after ~15s):
dns-sd -B _scanner._tcp local.
```

You should see an instance such as `Canon-MG6250`. Resolve details:

```bash
dns-sd -L "Canon-MG6250" _scanner._tcp local.
```

**Image Capture UI:** network scanners usually appear under **Shared** (remote/Bonjour device), not under **Devices** (direct/USB). That label is normal; it does not mean another Mac is sharing the scanner.

**Recommended install order:** deploy the **printer** queue first (network printing), then **`deploy_canon_scanner.sh --headless-scan`** for scan. One physical printer shows up **twice** in Image Capture (registered BJNP entry + Bonjour browse). The MG6250 allows **one** active BJNP scan session — if scan fails with Canon’s generic “cannot communicate” dialog (−9933):

1. Quit **Image Capture** (the Canon module services one client — an open GUI blocks scripted scans).
2. Scan the **registered** entry (`00000000-0000-0000-0000-3631…`) — the Bonjour entry (`615F1D00-…`) fails −9933 with or without `CIJScannerRegister` running (measured 2026-10-12 04:13 BST).
3. If the registered entry doesn’t appear in `ICDeviceBrowser` (typically only after a reboot), seed it: `open -a "/Library/Image Capture/Support/LegacyDeviceDiscoveryHelpers/CIJScannerRegister.app"`, wait ~15 s, then scan. The registration persists in the ICA cache after the daemon quits — it does not need to keep running.
4. If it *still* fails: let the module exit on its own, **wait ~5 minutes without any attempt**, then run once. Do not loop retries.

**Scripted scan:** [`scan_network_test.swift`](scanner-driver/scan_network_test.swift) browses with `ICDeviceBrowser` (mask `0xF02`), opens the session on the **registered entry** (`00000000-0000-0000-0000-3631…` uuid, served by `CIJScannerRegister`), waits 2 s after unit selection before `requestScan`, and **closes the ICA session gracefully** on completion so the next scan does not need `pkill` or a cool-down:

```bash
swift scan_network_test.swift                                   # registered entry, output /tmp/canon-scan-out/
swift scan_network_test.swift 00000000-0000-0000-0000-3631 2 myscan   # uuid prefix, pre-scan delay, output basename
```

**Which entry matters (measured 2026-10-12 ~03:52–04:30 BST):** the two ICA entries (`Bonjour 615F1D00-…` and registered `…363135463144`) use **different transport plugins with different lifetimes** — on the Bonjour entry, `cijsdj_bjnp.plugin` is destroyed the instant its slow (17–22 s) session setup completes, so `requestScan` fires with no transport and ICA surfaces the module's error as `-9933`; the registered entry presents as a local device, loads `cijsdj_iom.plugin`, and keeps its transport for the whole session. Scans via the **registered** entry succeeded 6× in a row (~10–15 s each, USB unplugged) — **including with `CIJScannerRegister` quit** (its registration persists in the ICA cache; the daemon is only needed to seed it, e.g. after a reboot). The **Bonjour** entry is non-deterministic: it worked twice at ~03:06 with instant (20 ms) session setup, and failed every time when setup took 17–22 s. The success signature is the warm-up pair in the log: `Scanner is warming up` → `ICScannerStatusWarmUpDone` → `SCAN COMPLETE error: nil`. Also required: **Image Capture GUI closed** (the Canon module services one client — an open GUI makes the CLI session hang at `requestOpenSession` with no callback).

If it still reports −9933 (“cannot communicate”), check in order: (1) Image Capture GUI closed, (2) the registered entry exists — if not (e.g. fresh reboot), seed it with `open -a "/Library/Image Capture/Support/LegacyDeviceDiscoveryHelpers/CIJScannerRegister.app"`, wait ~15 s, (3) the printer is serving a stale session — quit Image Capture, let the module exit on its own, **wait ~5 minutes without any attempt** (including GUI), then run it once. Do not loop retries.

**Firewall:** macOS application firewall rarely blocks outbound mDNS; if you use third-party security software, allow local network / multicast.

## Quick start - printer

The printer DMG should be at `printer-driver/mcpd-mac-mg6200-16_20_0_0-ea21_3.dmg`.

**Bonjour / network (no existing queue):**

```bash
cd /path/to/canon-mg6250-mac-driver-bundle/printer-driver
./install_canon_mg6250_bonjour_network.sh
```

Test print:

```bash
lp -d Canon-MG6250-Bonjour-Network /path/to/file.pdf
```

**Queue name vs display name:** CUPS queue IDs cannot contain spaces or parentheses. The script creates queue **`Canon-MG6250-Bonjour-Network`** and sets the friendly title **`Canon-MG6250 (Bonjour Network)`** via `lpadmin -D`.

**After install — tidy queues and names:** macOS often adds extra printers alongside the Bonjour queue (e.g. an AirPrint entry named after your Mac, or a **USB** queue when the cable is plugged in). Those use colour defaults and are easy to pick by mistake in Preview. List queues with `lpstat -p -v` and remove duplicates only if you are sure (removing a queue does not uninstall the Canon driver):

```bash
# Optional: remove a USB queue if you only use Wi-Fi (example ID — check lpstat -p first)
sudo lpadmin -x Canon_MG6200_series
```

Rename the bundle queue for clarity (queue ID unchanged):

```bash
sudo lpadmin -p Canon-MG6250-Bonjour-Network -D 'Canon-MG6250 (Bonjour Network - Mono)'
```

Use **System Settings → Printers** or `lpstat -p` to see queue IDs. Only the Bonjour queue with the Canon PPD has grayscale-on defaults; keep that one as your everyday printer. Removing a queue does **not** uninstall `/Library/Printers/Canon/BJPrinter` or the ICA scanner module.

**Manual workflow** (custom URI or queue name):

```bash
cd /path/to/canon-mg6250-mac-driver-bundle/printer-driver
./deploy_printer_canon_full.sh
./add_canon_mg6250_official_queue.sh 'ipp://Canon-MG6250.local:631/ipp/printer' MyQueueID 'My Display Name'
```

Dry-run extract only (no copy to `/Library`): `DRY_RUN=1 ./deploy_printer_canon_full.sh`

## Other scripts (printer)

| Script | Purpose |
|--------|---------|
| [`deploy_printer_canon_full.sh`](printer-driver/deploy_printer_canon_full.sh) | Full `BJPrinter` tree + official gzipped PPD |
| [`add_canon_mg6250_official_queue.sh`](printer-driver/add_canon_mg6250_official_queue.sh) | Add a queue with the Canon PPD |
| [`deploy_printer_driver.sh`](printer-driver/deploy_printer_driver.sh) | Legacy: filters (+ optional scanner from printer folder); often insufficient alone on modern macOS |
| [`restore_canon_mg6250_test_airprint.sh`](printer-driver/restore_canon_mg6250_test_airprint.sh) | Restore `.ppd.bak` for a patched test queue |

Scanner helper: [`verify_network_scan.sh`](scanner-driver/verify_network_scan.sh) — bounded mDNS + BJNP probe before using Image Capture over Wi‑Fi.

## Grayscale and black-and-white printing

By default the Canon PPD prints in **colour** (`*DefaultColorModel: RGB16`, `*DefaultCNIJGrayScale: 0`). With grayscale **off**, "black" text is reproduced as **composite colour** - a mix of cyan/magenta/yellow dye inks plus black - which looks muddy and wastes colour ink. `install_canon_mg6250_bonjour_network.sh` therefore sets grayscale **on** as the queue default so everyday documents use the **pigment black (PGBK)** cartridge only.

Grayscale on this PPD needs **all three** of these options set together:

```bash
sudo lpadmin -p Canon-MG6250-Bonjour-Network \
  -o CNIJGrayScale=1 -o CNIJGrayScaleCheckBox=1 -o CNIJRGB2GrayConvert=1
```

`CNIJRGB2GrayConvert=1` is the one that's easy to miss - without it the filter still processes colour raster data and the printer pulls colour inks even though grayscale "looks" enabled.

**Duplex forces colour ink (important):** auto-duplex on the MG6250 switches to the **fast-drying dye inks** (composite black = C+M+Y) instead of pigment black, because PGBK pigment can't dry quickly enough to flip the sheet. The result is a yellow/grey tint on B&W text. **Do not** bake auto-duplex into the queue default if you want pure black. For true-black double-sided output, use **manual duplex**: Print dialog -> **Paper Handling** -> **Pages to Print: Odd Only**, flip the stack, then print **Even Only** (each pass is single-sided, so PGBK is used both times).

**Printing a colour job occasionally** (overrides the grayscale default for one job):

```bash
lp -d Canon-MG6250-Bonjour-Network \
  -o CNIJGrayScale=0 -o CNIJRGB2GrayConvert=0 /path/to/photo.pdf
```

Or untick **Grayscale Printing** under **Color Options** in the macOS Print dialog.

## Addendum: implementation notes

- Canon PPD grayscale requires ALL THREE options: `CNIJGrayScale=1`, `CNIJGrayScaleCheckBox=1`, AND `CNIJRGB2GrayConvert=1` - the last is critical but easily missed
- macOS print job presets (`~/Library/Preferences/com.apple.print.custompresets*.plist`) are unreliable - CUPS queue defaults via `lpadmin -o` are authoritative
- Canon's PDE (Print Dialog Extension) does not reliably respond to quality-related queue defaults - avoid baking quality settings into deploy scripts
- `install_canon_mg6250_bonjour_network.sh` is the primary deployment entry point for the printer
- Scripts need `sudo` - use `osascript ... with administrator privileges` for GUI sudo in non-interactive shells (e.g. Cursor agent)
- Driver tree and PPD persist across queue removal - no need to redeploy `/Library/Printers/Canon/BJPrinter` if already present

## Caveats

- Classic **PPD-based** drivers may be deprecated in a future CUPS; **driverless IPP** is Apple’s long-term direction.
- This is **not** a full Canon `.pkg` install (e.g. no legacy USB kext path); **network IPP** is the primary target for printing.

## License

- **Scripts and documentation** in this repository: [**MIT**](LICENSE).
- **Canon DMG files** and anything extracted from them: **Canon’s terms only** - see [**CANON_DMG_NOTICE.md**](CANON_DMG_NOTICE.md).

Local build artifacts are listed in [`.gitignore`](.gitignore) (`canon_tmp/`, etc.).
