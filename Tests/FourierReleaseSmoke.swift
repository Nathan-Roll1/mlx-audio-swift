import Foundation
import MLX
import Testing
@testable import MLXAudioSTT

struct FourierReleaseSmoke {
    @Test func decodeJFK() async throws {
        let fixture = URL(fileURLWithPath: "/tmp/fourier-swift-fixture")
        let model = try await Qwen3ASRModel.fromModelDirectory(fixture.appendingPathComponent("model"))
        let data = try Data(contentsOf: fixture.appendingPathComponent("audio.s16le"))
        let pcm = data.withUnsafeBytes { bytes in
            stride(from: 0, to: bytes.count, by: 2).map { index in
                Float(Int16(littleEndian: bytes.loadUnaligned(fromByteOffset: index, as: Int16.self))) / 32768
            }
        }
        let out = model.generate(audio: MLXArray(pcm), maxTokens: 70, language: "English")
        print("SWIFT_FOURIER_JFK", out.text)
        #expect(out.text.localizedCaseInsensitiveContains("country"))
        #expect(out.text.localizedCaseInsensitiveContains("Americans"))
    }
}
