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
        guard button.waitForExistence(timeout:60) else { print(app.debugDescription.prefix(18000));return XCTFail("File transcription button unavailable") }
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == YES"), object: button)
        guard XCTWaiter.wait(for: [ready], timeout: 120) == .completed else {
            print(app.debugDescription.prefix(18000))
            return XCTFail("File transcription control disabled after plugin load")
        }
        button.click()
        let stop=Date().addingTimeInterval(100)
        while Date()<stop {
            let paths=(try? FileManager.default.contentsOfDirectory(at:wav.deletingLastPathComponent(),includingPropertiesForKeys:nil)) ?? []
            for path in paths where ["txt","md"].contains(path.pathExtension) && path.lastPathComponent.lowercased().contains("jfk") {
                if let txt=try? String(contentsOf:path),txt.lowercased().contains("what your country can do for you") { print("SIGNED_GUI_TRANSCRIPT", path.lastPathComponent,txt); return }
            }
            if app.debugDescription.lowercased().contains("what your country can do for you") {print("SIGNED_GUI_TRANSCRIPT",app.debugDescription.prefix(12000));return}
            RunLoop.current.run(until:Date().addingTimeInterval(2))
        }
        print(app.debugDescription.prefix(18000))
        XCTFail("No transcript was visible or exported by the desktop app.")
    }
}
