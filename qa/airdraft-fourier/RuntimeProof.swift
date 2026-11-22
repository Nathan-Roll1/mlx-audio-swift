import XCTest
@testable import AirdraftCore

extension GGUFModelTests {
    @MainActor func testFourierDownloadAndOfflineDecodeOnAppleSilicon() async throws {
        let model = try XCTUnwrap(GGUFModelCatalog.model("oruk-fourier-2b"))
        try await ModelDownloader.shared.download(model.config, progress: { _ in })
        XCTAssertTrue(LocalModels.isInstalled(model.config))
        let recognizer = GGUFTranscriber(modelID: model.id)
        try await recognizer.prepare()
        let dirs = URL(fileURLWithPath:#filePath).deletingLastPathComponent()
        let clips = [("jfk", "and so my fellow americans ask not what your country can do for you ask what you can do for your country"), ("fleurs", "however due to the slow communication channels styles in the west could lag behind by twenty five to thirty years")]
        for (name, expected) in clips {
            let path = dirs.appendingPathComponent("qa-fixtures/\(name).wav").path
            let samples = try AudioFile.load(path:path)
            let result = try await recognizer.transcribe(samples:samples, hints:TranscriptionHints(language:"en"))
            let normalized = result.text.lowercased().split { !$0.isLetter }.joined(separator:" ")
            XCTAssertEqual(normalized, expected)
            XCTAssertEqual(result.language, "en")
            print("FOURIER_APP_RESULT \(name) \(samples.count) \(result.text)")
        }
        await recognizer.unload()
    }
}
