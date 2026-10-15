# Network scanning: findings from getting the MG6250 to scan on macOS 26

Tested on macOS Tahoe 26.7, Apple Silicon, with Canon's last Mac scanner
driver (the High Sierra build in this folder). Printing was never a problem:
the Bonjour/IPP queue prints reliably. Scanning over the network was the hard
part. These are the results of several debugging sessions in October 2026,
including packet captures and disassembly of Canon's scanner module.

## The procedure that works

```bash
./deploy_canon_scanner.sh --network
# Close the Image Capture GUI, then:
swift scan_network_test.swift
```

`scan_network_test.swift` browses with `ICDeviceBrowser` (mask `0xF02`), picks
the **registered** device entry (uuid starting `00000000-0000-0000-0000-3631`),
opens the session, waits 2 s after unit selection, scans the full platen at
150 dpi, and closes the session gracefully on the way out. A scan takes about
15 seconds. Success looks like this in the output:

```
STATUS: Scanner is warming up. -> ICScannerStatusWarmUpDone
SCAN COMPLETE error: nil
```

No warm-up pair means the job never started.

## Two entries appear; only one scans

The same physical scanner shows up twice in Image Capture:

- **Registered entry** (`00000000-0000-0000-0000-363135463144`), published by
  `CIJScannerRegister.app`, which the deploy script installs as a LaunchAgent.
  This is the entry that scans, every time.
- **Bonjour entry** (`615F1D00-...`), built from the printer's
  `_scanner._tcp` advertisement on UDP 8612. This entry fails with
  ICA error -9933 ("cannot communicate") essentially every time.

`CIJScannerRegister` only needs to run long enough to seed the entry; the
registration persists in Image Capture's cache after the daemon quits. After
a reboot, launch it once and wait about 15 seconds. If you plug the printer
in over USB as well, the registered entry is served by a real USB transport,
which is the most reliable configuration of all.

## Rules that keep it working

- **Close the Image Capture GUI before scripted scans.** The Canon module
  services one client. With the GUI open, a CLI session hangs silently at
  `requestOpenSession`.
- **Do not retry in a loop.** The printer serves one scan session. Killing
  the module mid-session or hammering retries leaves the printer busy for
  minutes, and each failed retry extends the window. If things wedge, quit
  Image Capture, let the module exit on its own, wait five minutes with no
  scan attempts, then try once.
- **Close the session gracefully** when scripting. The bundled script calls
  `requestCloseSession`; scripts that skip it leave the printer's session
  allocated.

## Why the Bonjour entry fails (the interesting part)

Packet captures during failing Bonjour scans show the scan command never
leaves the Mac: no session-open request, no TCP to port 8612, nothing. The
17 to 22 seconds of "session setup" is the module's own discovery loop: three
passes, seven seconds each, probing the network and matching the printer by
MAC address against whatever it found.

The printer never makes it onto that list. Disassembling
`cijsdj_bjnp.plugin` shows why. The module speaks Canon's BJNPe dialect:
little-endian command words and reply fields throughout. The MG6250 firmware
speaks BJNP2: big-endian. The module's discovery probes use a reversed
`PNJB` magic and get header-only replies with no MAC or IP payload, so the
list stays empty. Patching the probe magic makes the printer answer with real
data, but the module's reply validator compares big-endian wire bytes as
little-endian and can never accept them. The session-open command word, the
session-id parsing, and the TCP scan-data phase all carry the same
assumption. Fixing it means byte-order shims at around a dozen interdependent
sites across the whole transport. We patched three stages in (teardown
suppression, discovery dialect, session-open magic) and confirmed each stage
on the wire; the conclusion held at every depth.

So: the Bonjour entry is not misconfigured or flaky, it is a protocol
mismatch between Canon's own driver and Canon's own firmware. The `-9933`
itself is Apple's `ICReturnReceivedUnsolicitedScannerErrorInfo`; the
"cannot communicate" text is Canon module error string `ICA_ERROR_40`.

One diagnostic hint worth knowing for other Canon models: the printer's
`GET_ID` reply advertises its dialects in the `SOJ:` field
(`SOJ:BJNP2,BJNPe` here). A model that answers in the dialect its driver
speaks would presumably behave better.

## What we ruled out

The firewall, mDNS configuration, CUPS, printer busy state (status probes
came back clean during every failure), driver age (the x86_64 plugin runs
fine under Rosetta), and the printer itself. Direct BJNP2 probes from the
Mac get instant replies, and a hand-rolled session open is granted
immediately, so the printer's scan service is healthy. The 8612/TCP
"connection refused" seen when idle is normal: the printer only listens on
TCP while a BJNP session is allocated.
