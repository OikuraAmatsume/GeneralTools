import AVFoundation
import Foundation
import Speech

@main
struct SpeechProbe {
    static func main() async {
        do {
            guard #available(macOS 26.0, *) else { return }
            print("SpeechAnalyzer available: \(Speech.SpeechTranscriber.isAvailable)")
            for identifier in ["zh-CN", "en-US", "ja-JP"] {
                guard let locale = await Speech.SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: identifier)) else {
                    print("\(identifier): unsupported")
                    continue
                }
                let module = Speech.SpeechTranscriber(locale: locale, preset: .transcription)
                print("\(identifier): \(await AssetInventory.status(forModules: [module]))")
            }
            guard CommandLine.arguments.count > 1 else { return }
            let audioURL = URL(fileURLWithPath: CommandLine.arguments[1])
            let file = try AVAudioFile(forReading: audioURL)
            print("Audio seconds: \(Double(file.length) / file.processingFormat.sampleRate)")
            let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
            try file.read(into: buffer)
            if let samples = buffer.floatChannelData?.pointee {
                var energy: Double = 0
                var peak: Float = 0
                for i in 0..<Int(buffer.frameLength) {
                    energy += Double(samples[i] * samples[i])
                    peak = max(peak, abs(samples[i]))
                }
                print("Audio RMS: \(sqrt(energy / Double(buffer.frameLength))), peak: \(peak)")
            }
            guard CommandLine.arguments.count > 2 else { return }
            let locale = await Speech.SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "zh-CN"))!
            let module = Speech.SpeechTranscriber(locale: locale, preset: .transcription)
            try await AssetInventory.reserve(locale: locale)
            if let install = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
                print("Downloading local Chinese model…")
                try await install.downloadAndInstall()
            }
            let analyzer = SpeechAnalyzer(modules: [module])
            let resultTask = Task { () throws -> String in
                var transcript = ""
                for try await result in module.results {
                    if result.isFinal {
                        transcript += String(result.text.characters) + "\n"
                        print("Final result: \(result.text.characters.count) characters")
                    }
                }
                return transcript
            }
            file.framePosition = 0
            try await analyzer.start(inputAudioFile: file, finishAfterFile: true)
            let text = try await resultTask.value
            try text.write(toFile: CommandLine.arguments[2], atomically: true, encoding: .utf8)
            print("Saved transcript: \(text.count) characters")
        } catch {
            let error = error as NSError
            print("FAILED: \(error.domain) \(error.code) \(error.localizedDescription)")
            exit(1)
        }
    }
}
