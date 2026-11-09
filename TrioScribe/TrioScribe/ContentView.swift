import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: 260)

            Divider()

            TranscriptWorkspace()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            SettingsPanel()
                .frame(width: 280)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .alert(
            "TrioScribe",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("好") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

private struct SidebarView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("TrioScribe")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .padding(.top, 18)

            VStack(spacing: 8) {
                ForEach(CaptureMode.allCases) { mode in
                    Button {
                        model.mode = mode
                    } label: {
                        Label(mode.rawValue, systemImage: mode.systemImage)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(model.mode == mode ? .accentColor : Color(nsColor: .controlColor))
                    .foregroundStyle(model.mode == mode ? .white : .primary)
                    .disabled(model.state != .idle)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("音频来源")
                        .font(.headline)
                    Spacer()
                    Button {
                        Task { await model.refreshApplications() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .help("刷新应用列表")
                }

                Picker("音频来源", selection: $model.selectedProcessID) {
                    Text("全部系统声音").tag(Int32(0))
                    Divider()
                    ForEach(model.applications) { application in
                        Text(application.name).tag(application.processID)
                    }
                }
                .labelsHidden()
                .disabled(model.state != .idle && model.state != .paused)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("本次记录")
                    .font(.headline)

                Label(model.language.displayName, systemImage: "captions.bubble")
                Label(model.elapsedLabel, systemImage: "clock")
                Label("本机处理", systemImage: "lock.shield")
            }
            .foregroundStyle(.secondary)

            Spacer()

            Text("系统收音需要在“系统设置 → 隐私与安全性”中授权。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .background(Color(nsColor: .underPageBackgroundColor))
    }
}

private struct TranscriptWorkspace: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            waveform
            controls
            Divider()
            transcript
            Divider()
            footer
        }
    }

    private var header: some View {
        HStack {
            Text("实时文字稿")
                .font(.system(size: 26, weight: .bold))

            Spacer()

            HStack(spacing: 8) {
                Circle()
                    .fill(model.state == .capturing ? Color.green : Color.secondary)
                    .frame(width: 8, height: 8)
                Text(model.statusLabel)
            }
            .font(.callout.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.thinMaterial, in: Capsule())

            Text(model.elapsedLabel)
                .font(.system(.title3, design: .monospaced).weight(.semibold))
                .frame(width: 92, alignment: .trailing)
        }
        .padding(24)
    }

    private var waveform: some View {
        WaveformView(level: model.audioLevel, isActive: model.state == .capturing)
            .frame(height: 108)
            .padding(.horizontal, 24)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            if model.mode == .importMedia {
                importControls
            } else {
                liveControls
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }

    @ViewBuilder
    private var liveControls: some View {
        switch model.state {
            case .idle:
                Button {
                    Task { await model.startNewSession() }
                } label: {
                    Label("开始收音", systemImage: "waveform.circle.fill")
                        .frame(minWidth: 120)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

            case .capturing:
                Button {
                    Task { await model.pauseSession() }
                } label: {
                    Label("暂停", systemImage: "pause.fill")
                        .frame(minWidth: 100)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    Task { await model.endSession() }
                } label: {
                    Label("结束", systemImage: "stop.fill")
                        .frame(minWidth: 90)
                }
                .controlSize(.large)

            case .paused:
                Button {
                    Task { await model.resumeSession() }
                } label: {
                    Label("继续", systemImage: "play.fill")
                        .frame(minWidth: 100)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    Task { await model.endSession() }
                } label: {
                    Label("结束", systemImage: "stop.fill")
                        .frame(minWidth: 90)
                }
                .controlSize(.large)

            case .starting, .importing, .stopping:
                ProgressView()
                    .controlSize(.small)
                Text(model.statusLabel)
                    .foregroundStyle(.secondary)
                if model.state == .starting {
                    Button("取消") { Task { await model.cancelImport() } }
                }
        }
    }

    @ViewBuilder
    private var importControls: some View {
        if model.state == .importing {
            ProgressView()
                .controlSize(.small)
            Text(model.importedFileName ?? "正在处理文件")
                .foregroundStyle(.secondary)
            Button("取消") {
                Task { await model.cancelImport() }
            }
        } else {
            Button {
                Task { await model.importMedia() }
            } label: {
                Label("选择视频或音频", systemImage: "square.and.arrow.down")
                    .frame(minWidth: 150)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.state != .idle)
        }
    }

    private var transcript: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if model.segments.isEmpty && model.partialTranscript.isEmpty {
                    ContentUnavailableView(
                        model.currentSessionDirectory == nil ? "等待声音" : "暂无文字",
                        systemImage: "waveform",
                        description: Text(
                            !model.sessionMessage.isEmpty ? model.sessionMessage : model.mode == .live
                                ? "选择播放视频的应用，然后点击“开始收音”。"
                                : "选择本地视频或音频文件以生成文字稿。"
                        )
                    )
                    .frame(maxWidth: .infinity, minHeight: 290)
                }

                ForEach(model.segments) { segment in
                    TranscriptRow(segment: segment)
                    Divider()
                }

                if !model.partialTranscript.isEmpty {
                    HStack(alignment: .top, spacing: 14) {
                        Text(model.elapsedLabel)
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 58, alignment: .leading)

                        VStack(alignment: .leading, spacing: 8) {
                            Text(model.partialTranscript)
                                .font(.body)
                                .textSelection(.enabled)
                            Label("识别中…", systemImage: "sparkles")
                                .font(.caption)
                                .foregroundStyle(.tint)
                        }
                    }
                    .padding(18)
                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    .padding(16)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Label("桌面/TrioScribe", systemImage: "externaldrive.fill.badge.checkmark")
                .foregroundStyle(.secondary)
            Spacer()
            Button("打开文件夹") { model.openSessionFolder() }
            Button("查看文字稿") { model.openTranscript() }
                .disabled(model.currentSessionDirectory == nil)
            Button("导出") {
                model.exportTranscript()
            }
                .buttonStyle(.borderedProminent)
                .disabled(model.segments.isEmpty)
        }
        .padding(16)
    }
}

private struct TranscriptRow: View {
    let segment: TranscriptSegment

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Button { } label: {
                Image(systemName: "play.circle")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Text(segment.timestampLabel)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .leading)

            Text(segment.text)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }
}

private struct SettingsPanel: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("转写设置")
                .font(.system(size: 22, weight: .bold))
                .padding(.top, 24)

            VStack(alignment: .leading, spacing: 8) {
                Text("识别语言")
                    .font(.headline)
                Picker("识别语言", selection: $model.language) {
                    ForEach(TranscriptionLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .labelsHidden()
                .disabled(model.state != .idle && model.state != .paused)
            }

            Divider()

            Label("自动标点", systemImage: "textformat.abc")
            Label("自动保存音频", systemImage: "waveform.badge.checkmark")
            Text(model.outputDirectoryPath)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            Divider()

            VStack(alignment: .leading, spacing: 9) {
                Text("识别引擎")
                    .font(.headline)
                Text(model.engineDescription)
                    .font(.callout)
                Text(model.recognitionStatus)
                    .foregroundStyle(.secondary)
                    .font(.callout)
                Text("支持中文、英语和日语。首次使用某种语言时会下载 Apple 本地模型，之后在本机转写。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !model.sessionMessage.isEmpty {
                    Text(model.sessionMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Spacer()

            Text("TrioScribe 0.1.2")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .background(Color(nsColor: .underPageBackgroundColor))
    }
}

private struct WaveformView: View {
    let level: Float
    let isActive: Bool

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<64, id: \.self) { index in
                    WaveformBar(
                        index: index,
                        availableWidth: geometry.size.width,
                        maximumHeight: geometry.size.height,
                        level: level,
                        isActive: isActive
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 16)
            .background(Color.accentColor.opacity(0.055), in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.accentColor.opacity(0.12))
            }
            .animation(.easeOut(duration: 0.16), value: level)
        }
    }
}

private struct WaveformBar: View {
    let index: Int
    let availableWidth: CGFloat
    let maximumHeight: CGFloat
    let level: Float
    let isActive: Bool

    private var barWidth: CGFloat {
        max(2, (availableWidth - 189) / 64)
    }

    private var barHeight: CGFloat {
        let phase = abs(sin(Double(index) * 0.68))
        let activity = isActive ? max(Double(level), 0.08) : 0.04
        return max(4, maximumHeight * activity * (0.35 + phase * 0.65))
    }

    var body: some View {
        Capsule()
            .fill(index % 5 == 0 ? Color.teal : Color.accentColor)
            .frame(width: barWidth, height: barHeight)
    }
}


