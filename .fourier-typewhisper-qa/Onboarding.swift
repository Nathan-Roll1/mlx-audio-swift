import AppKit
import CoreGraphics
import XCTest

final class Onboarding: XCTestCase {
    func testOrdinaryPermissionPrompt() throws {
        let app = XCUIApplication(bundleIdentifier: "com.typewhisper.mac")
        app.launch()
        let button = app.buttons.matching(NSPredicate(format: "label ==[c] 'Grant Microphone Access' OR title ==[c] 'Grant Microphone Access'")).firstMatch
        guard button.waitForExistence(timeout: 15) else {
            print("PERMISSION_PROBE_WIZARD", app.debugDescription.prefix(20000))
            return XCTFail("Could not locate signed app's permission button")
        }
        print("PERMISSION_PROBE_APP_BUTTON", button.debugDescription)
        var observed = false
        let interruption = addUIInterruptionMonitor(withDescription: "TypeWhisper microphone request") { panel in
            let text = panel.debugDescription
            guard text.lowercased().contains("microphone"), text.lowercased().contains("typewhisper") else {return false}
            print("PERMISSION_PROBE_NATIVE_PROMPT", text.prefix(6000))
            observed = true
            // Leave the ordinary permission choice to a user; collect evidence only.
            return false
        }
        defer { removeUIInterruptionMonitor(interruption) }
        button.click()
        print("PERMISSION_PROBE_BUTTON_PRESSED")
        NSPasteboard.general.clearContents()
        _ = NSPasteboard.general.setString("fourier-record-permission-probe", forType: .string)
        sleep(3)
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let owners = Set(windows.compactMap { $0[kCGWindowOwnerPID as String] as? Int32 })
        for id in owners {
            guard let a = NSRunningApplication(processIdentifier: id), let bundle = a.bundleIdentifier else {continue}
            print("PERMISSION_PROBE_WINDOW", bundle)
            let interesting = ["securityagent", "usernotification", "controlcenter", "coreservicesuiagent", "tcc", "usernotifications", "notificationcenter"]
            guard interesting.contains(where: { bundle.lowercased().contains($0) }),
                  NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) != nil
            else {continue}
            // Read the ordinary accessibility tree only for the system-owned prompt.
            let other = XCUIApplication(bundleIdentifier: bundle)
            let tree = other.debugDescription
            if tree.lowercased().contains("microphone") {
                print("PERMISSION_PROBE_SYSTEM_UI", tree.prefix(14000))
                if tree.lowercased().contains("typewhisper") {observed = true}
            }
        }
        let tree = app.debugDescription
        print("PERMISSION_PROBE_STATUS", String(tree.prefix(9000)).replacingOccurrences(of: "\n", with: " "))
        print("PERMISSION_PROBE_PROMPT_OBSERVED", observed)
    }
}
