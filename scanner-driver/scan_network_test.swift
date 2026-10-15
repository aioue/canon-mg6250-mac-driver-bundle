import Foundation
import ImageCaptureCore
import AppKit

// Network scan test for Canon MG6250 on occam.
// Usage: scan_network_test.swift [uuidPrefix] [scanDelaySeconds] [outName]
//   uuidPrefix defaults to "00000000-0000-0000-0000-3631" (registered entry,
//   served by CIJScannerRegister). This is the proven-reliable path: with
//   CIJScannerRegister running, scans via the registered entry succeed
//   (twice verified 2026-10-12 ~03:52 BST; 2026-10-12 04:14 BST verified the
//   scan also works with CIJScannerRegister QUIT — its registration persists
//   in the ICA cache. The daemon is only needed to (re)seed that cache, e.g.
//   after a reboot) while the Bonjour entry
//   ("615F1D00") reliably fails -9933 — the two entries race for the
//   printer's single BJNP scan session. Requires: Image Capture GUI closed
//   (the module services one client).
//   scanDelaySeconds delays requestScan after the functional unit is
//   selected — 2 s is sufficient; the BJNP session may not be ready at
//   session-open.
// On completion (success or error) the ICA session is closed gracefully so the
// printer-side BJNP session is released and an immediate re-run does not need pkill.

let args = CommandLine.arguments
let uuidPrefix = args.count > 1 ? args[1] : "00000000-0000-0000-0000-3631"
let scanDelay = args.count > 2 ? Double(args[2]) ?? 2.0 : 2.0
let outName = args.count > 3 ? args[3] : "occam-test-scan"

// outName is joined under /tmp/canon-scan-out/ — reject paths early (before
// any BJNP session is opened) rather than failing at write time.
if outName.contains("/") {
    fputs("outName must be a basename (no '/')\n", stderr)
    exit(2)
}

// A nil didCompleteScanWithError is NOT success by itself — the module
// reports it even after -9933 with no file. Only a non-empty JPEG counts.
// Top-level so both the delegate and the timeout path can call it.
func scanFileOk() -> Bool {
    let path = "/tmp/canon-scan-out/\(outName).jpeg"
    let size = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int ?? 0
    return size > 0
}

final class Delegate: NSObject, ICDeviceBrowserDelegate, ICDeviceDelegate, ICScannerDeviceDelegate {
    var browser: ICDeviceBrowser?
    var scanner: ICScannerDevice?
    var closing = false

    func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
        print("DID ADD: \(String(describing: device.name)) | uuid: \(String(describing: device.uuidString))")
        guard device.uuidString?.hasPrefix(uuidPrefix) == true else { return }
        guard let scanner = device as? ICScannerDevice else { return }
        if self.scanner == nil {
            self.scanner = scanner
            scanner.delegate = self
            let dir = URL(fileURLWithPath: "/tmp/canon-scan-out")
            scanner.downloadsDirectory = dir
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            scanner.transferMode = .fileBased
            scanner.documentUTI = "public.jpeg"
            scanner.documentName = outName
            // Image Capture will not overwrite an existing documentName — it
            // writes "occam-test-scan 1.jpeg" instead, which would make the
            // exit check pass on a STALE file. Remove the old output first.
            try? FileManager.default.removeItem(atPath: "/tmp/canon-scan-out/\(outName).jpeg")
            print("OPEN SESSION REQUESTED for uuid \(uuidPrefix)")
            scanner.requestOpenSession { _ in print("open session requested") }
        }
    }
    func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {}
    func didRemove(_ device: ICDevice) {}

    func device(_ device: ICDevice, didOpenSessionWithError error: Error?) {
        print("OPEN SESSION: error=\(String(describing: error))")
    }
    func device(_ device: ICDevice, didCloseSessionWithError error: Error?) {
        print("CLOSE SESSION: error=\(String(describing: error))")
        exit(scanFileOk() ? 0 : 1)
    }
    func device(_ device: ICDevice, didReceiveStatusInformation status: [ICDeviceStatus: Any]) {
        print("STATUS: \(status)")
    }
    func device(_ device: ICDevice, didEncounterError error: Error?) {
        print("DEVICE ENCOUNTER ERROR: \(String(describing: error))")
    }

    func scannerDevice(_ scanner: ICScannerDevice, didSelect functionalUnit: ICScannerFunctionalUnit, error: Error?) {
        print("SELECTED UNIT type=\(functionalUnit.type.rawValue) error=\(String(describing: error))")
        print("measurementUnit raw: \(functionalUnit.measurementUnit.rawValue) | physicalSize: w=\(functionalUnit.physicalSize.width) h=\(functionalUnit.physicalSize.height)")
        functionalUnit.scanArea = NSMakeRect(0, 0, functionalUnit.physicalSize.width, functionalUnit.physicalSize.height)
        functionalUnit.resolution = 150
        // Delay the scan request: give the Canon BJNP module time to finish
        // session setup after open; a requestScan in the same runloop turn as
        // session-open produced ICA -9933 in earlier retries.
        let dl = scanDelay
        let end = Date().addingTimeInterval(dl)
        while Date() < end {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.2))
        }
        print("REQUEST SCAN (delayed \(dl)s)")
        scanner.requestScan()
    }
    func scannerDevice(_ scanner: ICScannerDevice, didCompleteScanWithError error: Error?) {
        print("SCAN COMPLETE error: \(String(describing: error))")
        let files = try? FileManager.default.contentsOfDirectory(atPath: "/tmp/canon-scan-out")
        print("FILES: \(String(describing: files))")
        if !closing {
            closing = true
            print("CLOSING SESSION")
            // didCloseSessionWithError often does not fire for this module
            // (it quits with "Servicing Zero Clients" right after the close
            // request), so exit from the completion handler.
            scanner.requestCloseSession { _ in exit(scanFileOk() ? 0 : 1) }
        }
        // didCloseSessionWithError exits (with file-check exit code); fall
        // back to hard exit if it never comes.
        let end = Date().addingTimeInterval(5)
        while Date() < end {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.2))
        }
        print("EXIT WITHOUT CLOSE CALLBACK")
        exit(scanFileOk() ? 0 : 1)
    }
}

let d = Delegate()
let b = ICDeviceBrowser()
b.delegate = d
b.browsedDeviceTypeMask = ICDeviceTypeMask(rawValue: 0x00000F02)!
d.browser = b
b.start()
print("browsing... uuidPrefix=\(uuidPrefix) scanDelay=\(scanDelay)")
let end = Date().addingTimeInterval(150)
while Date() < end {
    RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.5))
}
print("TIMEOUT - no scan completion")
exit(scanFileOk() ? 0 : 1)