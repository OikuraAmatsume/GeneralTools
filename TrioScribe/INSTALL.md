# Install TrioScribe 0.1.2

1. Download the Apple silicon DMG from the [TrioScribe 0.1.2 release](https://github.com/OikuraAmatsume/GeneralTools/releases/tag/trioscribe-v0.1.2) and open it.
2. Drag TrioScribe into the Applications folder.
3. Open TrioScribe and grant Screen & System Audio Recording permission if requested. Choose Chinese, English, or Japanese; the first use prepares the local model.
4. If macOS blocks this local test build, open System Settings → Privacy & Security and choose Open Anyway.

This package uses ad-hoc signing because no Apple Developer ID certificate is installed on the build Mac. It is intended for local testing and is not notarized for public distribution.

In the app, click “查看文字稿” to open `Transcript.md`, or “打开文件夹” to view the recording and transcript together. Wait for “正在完成文字稿” to finish after pressing Stop.

On macOS 14/15 or hardware without SpeechAnalyzer, enable Keyboard → Dictation and Speech Recognition permission. On supported macOS 26 hardware the new local engine does not depend on system Dictation.

