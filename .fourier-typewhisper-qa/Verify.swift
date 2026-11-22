import AppKit
import AVFoundation
import CryptoKit
import Foundation
import TypeWhisperPluginSDK

struct Failure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

@main
struct Verify {
    @MainActor static func main() async throws {
        let args = CommandLine.arguments
        let artifact = URL(fileURLWithPath: args[1])
        let dataDir = URL(fileURLWithPath: args[2])
        guard let bundle = Bundle(url: artifact) else { throw Failure("Plugin bundle missing") }
        try bundle.loadAndReturnError()
        guard let cls = NSClassFromString("Qwen3Plugin") as? TypeWhisperPlugin.Type else {
            throw Failure("Cannot load the signed Qwen3 plugin class")
        }
        let plugin = cls.init()
        guard let importer = plugin as? PluginCustomModelImporting, let engine = plugin as? TranscriptionEnginePlugin else { throw Failure("Plugin protocol mismatch") }
        let host = try PluginTestHostServices(pluginDataDirectory: dataDir, shouldRestoreLoadedModelsPassively: false)
        plugin.activate(host: host)
        let candidate = try await PluginModelImportCandidate.inspect(.huggingFace("oruk/oruk-fourier-2b"))
        guard candidate.modelType == "qwen3_asr", let revision = candidate.revision else { throw Failure("Source resolution failed") }
        let eligible = candidate.repositoryFiles.filter { path in
            !path.contains("/") && !path.contains("\\") && !path.hasPrefix(".") && ["json","safetensors","txt","model","tiktoken","wav"].contains((path as NSString).pathExtension.lowercased())
        }.sorted()
        guard eligible.filter({$0.hasSuffix(".safetensors")}) == ["model.safetensors"] else { throw Failure("Unexpected additional model assets") }
        print("CANDIDATE",revision,candidate.modelType,eligible); fflush(stdout)
        let record = try await importer.importModel(candidate, token: nil)
        print("IMPORTED",record.id,record.displayName); fflush(stdout)
        guard let scanner = FileManager.default.enumerator(at:dataDir,includingPropertiesForKeys:[.fileSizeKey]) else { throw Failure("Lost plugin data directory") }
        var localFiles:[String] = []
        var weightHashes:[String] = []
        for case let path as URL in scanner {
            if path.pathExtension == "safetensors" {
                let f = try FileHandle(forReadingFrom:path)
                var sha = SHA256()
                while let part = try f.read(upToCount:4*1024*1024), !part.isEmpty { sha.update(data:part) }
                try f.close()
                weightHashes.append(sha.finalize().map{String(format:"%02x",$0)}.joined())
                let bytes = try path.resourceValues(forKeys:[.fileSizeKey]).fileSize!
                guard bytes == 4076193080 else {throw Failure("Original model byte count differs")}
            }
            if !path.hasDirectoryPath { localFiles.append(path.lastPathComponent) }
        }
        guard weightHashes == ["e64765ffdd90c83704c0951e0d88b7f2ed84499af5c208f7ddf8d922cf08441c"] else { throw Failure("Unexpected weight checksum(s)") }
        for (filename, reference) in [(args[3],"And so my fellow Americans ask not what your country can do for you ask what you can do for your country"),(args[4],"To such persons these indirect modes of training children in habits of subordination to their will or rather of yielding to their influence are specially useful")] {
            let url = URL(fileURLWithPath:filename)
            let raw = try Data(contentsOf:url)
            let f = try AVAudioFile(forReading:url,commonFormat:.pcmFormatFloat32,interleaved:false)
            guard f.processingFormat.sampleRate == 16000, f.processingFormat.channelCount==1,let b = AVAudioPCMBuffer(pcmFormat:f.processingFormat,frameCapacity:AVAudioFrameCount(f.length)) else {throw Failure("WAV source format differs")}
            try f.read(into:b)
            let samples=Array(UnsafeBufferPointer(start:b.floatChannelData![0],count:Int(b.frameLength)))
            let audio=AudioData(samples:samples,wavData:raw,duration:Double(samples.count)/16000)
            let response=try await engine.transcribe(audio:audio,language:"en",translate:false,prompt:nil)
            let normal:(String)->[String] = { $0.lowercased().split { !$0.isLetter }.map(String.init) }
            print("SIGNED_PLUGIN_TRANSCRIPTION",url.lastPathComponent,response.text,normal(response.text).count); fflush(stdout)
            guard normal(response.text) == normal(reference) else { throw Failure("Reference mismatch on "+url.lastPathComponent) }
        }
        let recipe:[String:Any] = ["revision":revision,"files":localFiles.sorted(),"sha256":weightHashes,"id":record.id,"displayName":record.displayName,"host":"signed SDK from TypeWhisper v1.8.3 with official test host services","plugin":"signed v1.3.0","words":48]
        let data = try JSONSerialization.data(withJSONObject:recipe,options:[.sortedKeys])
        print("SIGNED_PLUGIN_RESULT="+String(decoding:data,as:UTF8.self)); fflush(stdout)
        // Keep the temporary SDK host alive until files and both in-process results are inspected.
        withExtendedLifetime(host) { exit(0) }
    }
}
