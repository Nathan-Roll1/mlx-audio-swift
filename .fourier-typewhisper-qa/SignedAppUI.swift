import AppKit
import XCTest
final class SignedAppUI: XCTestCase {
    func testFilesService() throws {
        let base=URL(fileURLWithPath:NSTemporaryDirectory()).deletingLastPathComponent()
        let shared=URL(fileURLWithPath:"/tmp/fourier-signed-ui-fixture.json")
        let cfg=try XCTUnwrap(try JSONSerialization.jsonObject(with:Data(contentsOf:shared)) as? [String:String])
        let app=XCUIApplication(bundleIdentifier:try XCTUnwrap(cfg["bundle"]))
        app.launch()
        XCTAssertTrue(app.wait(for:.runningForeground,timeout:15) || app.state == .runningBackground)
        let p=NSPasteboard.withUniqueName()
        let wav=URL(fileURLWithPath:try XCTUnwrap(cfg["wav"]))
        p.writeObjects([wav as NSURL])
        let svc=try XCTUnwrap(cfg["service"])
        print("SERVICES_NAME",svc,base.lastPathComponent)
        XCTAssertTrue(NSPerformService(svc,p),"Signed application file service failed")
        let button=app.buttons.matching(NSPredicate(format:"label CONTAINS[c] 'Transcribe All' OR title CONTAINS[c] 'Transcribe All'")).firstMatch
        guard button.waitForExistence(timeout:60) else { print("GUI_TREE " + app.debugDescription.prefix(21000).replacingOccurrences(of: "\n", with: "\nGUI_TREE "));return XCTFail("File transcription button unavailable") }
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == YES"), object: button)
        guard XCTWaiter.wait(for: [ready], timeout: 120) == .completed else {
            print("GUI_TREE " + app.debugDescription.prefix(21000).replacingOccurrences(of: "\n", with: "\nGUI_TREE "))
            return XCTFail("File transcription control disabled after plugin load")
        }
        button.click()
        let stop=Date().addingTimeInterval(170)
        while Date()<stop {
            let copy = app.buttons.matching(NSPredicate(format:"label BEGINSWITH[c] 'Copy transcript of'")).firstMatch
            if copy.exists && copy.isEnabled {
                copy.click()
                let txt = NSPasteboard.general.string(forType: .string) ?? ""
                if txt.lowercased().contains("what your country can do for you") {
                    print("SIGNED_GUI_TRANSCRIPT", txt)
                    let sink = XCUIApplication()
                    sink.launch()
                    let field = sink.textViews.firstMatch
                    XCTAssertTrue(field.waitForExistence(timeout: 10))
                    field.click()
                    field.typeKey("v", modifierFlags: .command)
                    let visible = field.value as? String ?? ""
                    XCTAssertTrue(visible.lowercased().contains("what your country can do for you"),visible)
                    print("SIGNED_GUI_PASTED", visible)
                    return
                }
            }
            let paths=(try? FileManager.default.contentsOfDirectory(at:wav.deletingLastPathComponent(),includingPropertiesForKeys:nil)) ?? []
            for path in paths where ["txt","md"].contains(path.pathExtension) && path.lastPathComponent.lowercased().contains("jfk") {
                if let txt=try? String(contentsOf:path),txt.lowercased().contains("what your country can do for you") { print("SIGNED_GUI_TRANSCRIPT", path.lastPathComponent,txt); return }
            }
            if app.debugDescription.lowercased().contains("what your country can do for you") {print("SIGNED_GUI_TRANSCRIPT",app.debugDescription.prefix(12000));return}
            RunLoop.current.run(until:Date().addingTimeInterval(2))
        }
        print("GUI_TREE " + app.debugDescription.prefix(21000).replacingOccurrences(of: "\n", with: "\nGUI_TREE "))
        XCTFail("No transcript was visible or exported by the desktop app.")
    }
}
