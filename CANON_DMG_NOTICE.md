# Canon driver disk images (third-party binaries)

This repository may include **two** official Canon disk images for the MG6200 series (e.g. PIXMA MG6250). Both are **Canon Inc.** software distributed for **macOS 10.13 (High Sierra)** and reused here only so the install scripts have predictable paths to the vendor payloads.

## Printer driver DMG

The file **`printer-driver/mcpd-mac-mg6200-16_20_0_0-ea21_3.dmg`** (or any replacement you ship under the same role) is the **Canon MG6200-series Mac printer driver**.

## Scanner driver DMG

The file **`scanner-driver/misd-mac-ijscanner1-4_0_0-ea19_2.dmg`** (or any replacement you ship under the same role) is the **Canon IJ Scanner** payload for the same product generation.

## Attribution and license

- **The contributors to this project did not write, compile, or own those DMGs.**
- **License:** Whatever terms Canon applies to each download (click-through, README, or license files **inside the mounted DMG or package**) apply to that DMG and everything extracted from it. **This project’s MIT [`LICENSE`](./LICENSE) does not cover Canon’s software.**
- **Trademarks:** “Canon”, model names, and related marks belong to Canon or their respective owners.

## If you cannot or should not use the copies in this repo

Replace them with files obtained from **Canon’s official support site** and point the scripts at them:

- Printer: `P_DMG=/path/to/your.dmg ./deploy_printer_canon_full.sh` (and the same variable for other printer scripts that support it).
- Scanner: edit or override the `DMG` variable at the top of `scanner-driver/deploy_canon_scanner.sh`, or place your file at the expected path and name.

If Canon requests removal of redistributed DMGs, remove them from your fork and rely on official downloads only.

This project is **not affiliated with or endorsed by Canon**.
