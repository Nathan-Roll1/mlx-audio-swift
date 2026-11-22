import AppKit
import CoreGraphics
import XCTest

final class Onboarding: XCTestCase {
    var imagesAvailable = true

    func receipt(_ stage: String) {
        print("CONSENT_STAGE", stage)
        let capture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        capture.name = stage
        capture.lifetime = .keepAlways
        add(capture)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("fourier-consent-" + stage, forType: .string)
    }

    func buttons(_ element: XCUIElement, _ label: String) -> XCUIElementQuery {
        element.buttons.matching(NSPredicate(format: "label ==[c] %@ OR title ==[c] %@ OR identifier ==[c] %@", label, label, label))
    }

    func permissionCard(_ app: XCUIApplication, _ prefix: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@", prefix)).firstMatch
    }

    func granted(_ card: XCUIElement) -> Bool {
        guard card.exists else { return false }
        return (card.value as? String)?.caseInsensitiveCompare("Granted") == .orderedSame
    }

    func stopPoint(_ description: String) {
        print("CONSENT_BOUNDARY",description)
        receipt("blocked")
        XCTFail(description)
    }

    func testOrdinaryPermissionPrompt() throws {
        let app = XCUIApplication(bundleIdentifier: "com.typewhisper.mac")
        app.launch()
        let request = buttons(app, "Grant Microphone Access").firstMatch
        guard request.waitForExistence(timeout: 15), request.isHittable else {
            return stopPoint("Signed onboarding microphone button unavailable.")
        }
        request.click()
        sleep(2)
        receipt("microphone-request")
        // The system dialog is expected. Query its ordinary accessibility controls directly.
        let wins = CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements], kCGNullWindowID) as? [[String:Any]] ?? []
        let owners = Set(wins.compactMap { $0[kCGWindowOwnerPID as String] as? Int32 })
        let ownersList = owners.compactMap { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier }
        print("CONSENT_VISIBLE_OWNERS",ownersList.sorted())
        var accepted = false
        let approvedDialogHosts = ["com.apple.UserNotificationCenter","com.apple.SecurityAgent","com.apple.CoreServicesUIAgent","com.apple.controlcenter","com.typewhisper.mac"]
        for bid in approvedDialogHosts where ownersList.contains(bid) {
            let candidate = XCUIApplication(bundleIdentifier: bid)
            guard candidate.state != .notRunning else { continue }
            let tree = candidate.debugDescription
            print("CONSENT_TREE",bid,String(tree.prefix(9500)).replacingOccurrences(of:"\n",with:" "))
            for window in candidate.windows.allElementsBoundByIndex + candidate.alerts.allElementsBoundByIndex {
                let text = window.debugDescription.lowercased()
                guard text.contains("typewhisper"),text.contains("microphone") else { continue }
                let allow = buttons(window,"Allow")
                let deny = buttons(window,"Don’t Allow").count + buttons(window,"Don't Allow").count
                guard allow.count == 1, deny > 0, allow.firstMatch.isHittable, allow.firstMatch.isEnabled else { continue }
                print("CONSENT_MIC_CONTROL",bid,allow.firstMatch.debugDescription)
                allow.firstMatch.click()
                accepted = true
                break
            }
            if accepted { break }
        }
        guard accepted else {
            return stopPoint("The expected Microphone sheet has no identified, enabled, hittable Allow control in the app or visible system windows. A person must use the normal macOS consent UI.")
        }
        let mic = permissionCard(app,"Microphone Access.")
        let limit = Date().addingTimeInterval(7)
        while Date() < limit && !granted(mic) { usleep(200000) }
        guard granted(mic) else { return stopPoint("The Allow control was selected, but TypeWhisper did not report Microphone Granted.") }
        print("CONSENT_MIC_GRANTED",mic.debugDescription)
        receipt("microphone-granted")
        let access = permissionCard(app,"Accessibility Access.")
        guard access.exists else { return stopPoint("TypeWhisper Accessibility control is absent.") }
        if !granted(access) {
            guard access.isHittable else { return stopPoint("TypeWhisper Accessibility request is not hittable.") }
            access.click()
            sleep(2)
            receipt("accessibility-request")
            let settings = XCUIApplication(bundleIdentifier:"com.apple.systempreferences")
            if settings.state == .notRunning || !settings.windows.firstMatch.exists {
                // macOS can offer a system prompt before opening the pane.
                for bid in ["com.apple.UserNotificationCenter","com.apple.SecurityAgent","com.typewhisper.mac"] {
                    let system = XCUIApplication(bundleIdentifier: bid)
                    guard system.state != .notRunning else { continue }
                    for win in system.windows.allElementsBoundByIndex {
                        let t = win.debugDescription.lowercased()
                        let go = buttons(win, "Open System Settings")
                        guard t.contains("typewhisper"), t.contains("accessibility"), go.count == 1, go.firstMatch.isHittable else { continue }
                        go.firstMatch.click()
                        break
                    }
                }
            }
            guard settings.windows.firstMatch.waitForExistence(timeout:6) else {
                return stopPoint("The normal Accessibility request did not expose System Settings.")
            }
            let t = settings.debugDescription
            print("CONSENT_SETTINGS",String(t.prefix(16000)).replacingOccurrences(of:"\n",with:" "))
            guard t.lowercased().contains("accessibility"),!t.lowercased().contains("securetextfield") else {
                return stopPoint("Accessibility pane unavailable or user authentication required.")
            }
            let byName = NSPredicate(format:"label CONTAINS[c] 'TypeWhisper' OR title CONTAINS[c] 'TypeWhisper' OR identifier CONTAINS[c] 'TypeWhisper'")
            let controls = [settings.switches.matching(byName), settings.checkBoxes.matching(byName)]
                .flatMap { $0.allElementsBoundByIndex }.filter { $0.isHittable && $0.isEnabled }
            guard controls.count == 1 else {
                return stopPoint("No unique accessible TypeWhisper permission switch in System Settings.")
            }
            guard String(describing:controls[0].value ?? "") == "0" else {
                return stopPoint("Cannot establish whether TypeWhisper’s Accessibility switch is off.")
            }
            controls[0].click()
            sleep(2)
            if settings.secureTextFields.count > 0 || XCUIApplication(bundleIdentifier:"com.apple.SecurityAgent").state == .runningForeground {
                return stopPoint("macOS requests interactive administrator authentication to authorize Accessibility.")
            }
            app.activate()
            let until = Date().addingTimeInterval(8)
            while Date() < until && !granted(access) { usleep(200000) }
        }
        guard granted(access) else {return stopPoint("The normal app does not report Accessibility Granted.")}
        print("CONSENT_BOTH_GRANTED",mic.debugDescription,access.debugDescription)
        receipt("both-granted")
    }
}
