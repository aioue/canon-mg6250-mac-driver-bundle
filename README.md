# Canon PIXMA MG6250 - macOS printer and scanner install kit

Unofficial scripts to install **Canon PIXMA MG6250** (MG6200-series) **printing** and **scanning** on **current macOS** using Canon’s **last official Mac drivers** - the **macOS 10.13 (High Sierra)** builds from Canon’s support site:

[Canon Europe - PIXMA MG6250 drivers (macOS 10.13)](https://www.canon-europe.com/support/consumer/products/printers/pixma/mg-series/pixma-mg6250.html?type=drivers&language=EN&os=macOS%2010.13%20(High%20Sierra))

**This project is not affiliated with or endorsed by Canon.**

## Testing and feedback

This has **only been tested on the maintainer’s setup** (including **macOS Tahoe 26.3** on **Apple Silicon** for the scanner path). Your mileage may vary. **Bug reports and pull requests are welcome.**

## What’s in this repository

| Path | Role |
|------|------|
| [`scanner-driver/`](scanner-driver/) | IJ Scanner install (`deploy_canon_scanner.sh`) and Canon scanner DMG |
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
./deploy_canon_scanner.sh
```

Then:

1. Unplug the USB scanner, wait a few seconds, plug it back in.
2. Open **Image Capture** and select the Canon scanner.
3. To debug: `log stream --predicate 'subsystem == "com.apple.ImageCaptureCore"'`

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
