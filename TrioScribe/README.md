# TrioScribe

TrioScribe is a native macOS app that captures audio from a browser or media player and turns speech into a timestamped transcript while the video is playing.

Download the Apple silicon disk image and its SHA-256 checksum from the [TrioScribe 0.1.2 release](https://github.com/OikuraAmatsume/GeneralTools/releases/tag/trioscribe-v0.1.2). This test build uses an ad hoc signature and has not been notarized by Apple.

## Current MVP

- Native SwiftUI desktop interface
- System-audio capture with ScreenCaptureKit
- Select a running browser or media application, or capture all system audio
- Live transcription in Chinese, English, or Japanese
- Import local audio or video files for transcription
- Automatically save live audio and transcripts under `~/Desktop/TrioScribe`
- Live input-level meter and elapsed time
- Timestamped transcript segments
- macOS 26: local SpeechAnalyzer recognition with automatic language-model preparation
- Visible recognition errors, final-result waiting, and buttons to open saved files
- Audio is transcribed on the Mac; no automatic cloud fallback

## Requirements

- macOS 14 or later
- Xcode 26 or later to build from source
- Screen & System Audio Recording permission
- On macOS 14/15 or unsupported hardware: Speech Recognition permission, enabled system Dictation, and a locally supported language

## Build

Open `TrioScribe.xcodeproj` and run the `TrioScribe` scheme, or build from Terminal:

```sh
xcodebuild -project TrioScribe.xcodeproj -scheme TrioScribe -configuration Release -derivedDataPath "$HOME/Desktop/TrioScribe/Build-0.1.2" CODE_SIGNING_ALLOWED=NO build
```

The first capture requests macOS permissions. If audio capture remains unavailable after permission is granted, restart the app once.

## Language support

- Chinese (`zh-CN`)
- English (`en-US`)
- Japanese (`ja-JP`)

The recognizer locale is selected before capture starts. Automatic mixed-language detection remains planned for the local Whisper engine integration.

## Saved files

Every live capture creates `~/Desktop/TrioScribe/Recording-YYYY-MM-DD_HH-mm-ss/` containing `Audio.wav` and `Transcript.md`. Imported media creates an `Import-...` session folder containing the transcript and, when video decoding is needed, `PreparedAudio.caf`. The source media remains in its original location. Empty/failed sessions include an explanatory status in the Markdown file.

Build products, test audio, logs, and packages for this repair are under `~/Desktop/TrioScribe`. Apple manages its shared language-model cache in the system's own location.

## 0.1.2: empty-transcript fix

The observed failure was `kLSRErrorDomain / 201` (Siri and Dictation disabled), which 0.1.1 discarded. On supported macOS 26 hardware, 0.1.2 uses SpeechAnalyzer and its local models instead of that legacy service. Chinese, English, and Japanese are selected before each session; automatic mixed-language detection is not included.

The app drains captured audio, finishes recognition, waits for final results, and then saves. It copies PCM buffers before asynchronous processing, retains multi-segment file results, and prevents cancelled operations from changing a new session. Legacy system Dictation failures are shown with actionable messages. The old engine can end a long session; the app now reports that termination instead of continuing silently.

Regression programs in `Diagnostics/` cover three-language recognition, streaming conversion, long recordings, cancellation, silence, imported segments, and error handling. `TranscriptionRegression` also accepts an optional path to a Chinese speech recording for a recovery check. The programs use local audio fixtures under `~/Desktop/TrioScribe/Diagnostics`.

