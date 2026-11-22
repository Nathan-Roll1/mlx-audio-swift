import AppKit
import XCTest

final class SignedAppUI: XCTestCase {
    func testRealMicrophone() throws {
        let app = XCUIApplication(bundleIdentifier: "com.typewhisper.mac")
        app.launch()
        let sink = XCUIApplication()
        sink.launch()
        let field = sink.textViews.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.click()
        let runner = Process()
        runner.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        runner.arguments = ["/tmp/fourier-typewhisper-mic.py"]
        try runner.run()
        let result = URL(fileURLWithPath: "/tmp/fourier-typewhisper-mic-result.json")
        let clock = Date().addingTimeInterval(150)
        var scanned = false
        while Date() < clock {
            if let bytes = try? Data(contentsOf: result), let state = (try? JSONSerialization.jsonObject(with: bytes)) as? [String:Any] {
                if state["stage"] as? String == "failure" {
                    return XCTFail("Signed microphone system failed: " + (state["detail"] as? String ?? "unknown"))
                }
                if state["stage"] as? String == "transcribed" {
                    guard let raw = state["text"] as? String, raw.lowercased().contains("what your country can do for you")
                    else {return XCTFail("Unexpected recording: " + (state["text"] as? String ?? "nil"))}
                    print("SIGNED_GUI_MIC_TRANSCRIPT", raw, state["model"] ?? "", state["engine"] ?? "")
                    let until = Date().addingTimeInterval(8)
                    while Date() < until {
                        if let visible = field.value as? String, visible.lowercased().contains("what your country can do for you") {
                            print("SIGNED_GUI_AUTOMATIC_MIC_PASTE", visible)
                            return
                        }
                        RunLoop.current.run(until: Date().addingTimeInterval(0.35))
                    }
                    // Only paste a transcript already placed on the clipboard by the app.
                    let clip = NSPasteboard.general.string(forType: .string) ?? ""
                    if clip.lowercased().contains("what your country can do for you") {
                        field.click()
                        field.typeKey("v", modifierFlags: .command)
                        let visible = field.value as? String ?? ""
                        XCTAssertTrue(visible.lowercased().contains("what your country can do for you"))
                        print("SIGNED_GUI_MANUAL_MIC_PASTE", visible)
                        return
                    }
                    return XCTFail("Released app captured the microphone transcript; external insertion was not observed.")
                }
            }
            if !scanned && Date() > clock.addingTimeInterval(-143) {
                scanned = true
                for identifier in ["com.apple.SecurityAgent", "com.apple.CoreServicesUIAgent", "com.apple.UserNotificationCenter"] {
                    let system = XCUIApplication(bundleIdentifier: identifier)
                    guard system.state == .runningForeground || system.state == .runningBackground else {continue}
                    let dialog = system.debugDescription.lowercased()
                    if dialog.contains("microphone") && dialog.contains("typewhisper") {
                        for name in ["Allow","OK"] where system.buttons[name].exists {
                            system.buttons[name].click()
                            print("SIGNED_GUI_NORMAL_MIC_AUTHORIZED")
                            break
                        }
                    }
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        XCTFail("The unmodified application did not return the microphone transcript in time.")
    }
}
