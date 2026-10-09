import AppKit
import SwiftUI

struct PanelHeader: View {
    var title: String
    var subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 24, weight: .semibold))
            Text(subtitle).font(.callout).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PlayerSettingsView: View {
    @ObservedObject var model: PlayerModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft: PlayerPreferences
    @State private var tab = 0
    init(model: PlayerModel, tab: Int = 0) { self.model = model; _draft = State(initialValue: model.preferences); _tab = State(initialValue: tab) }
    var body: some View {
        VStack(spacing: 20) {
            PanelHeader(title: "播放设置", subtitle: "为这台 Mac 保存偏好，所有游戏共用。")
            Picker("设置分类", selection: $tab) {
                Text("视频与画质").tag(0); Text("音频").tag(1); Text("性能 HUD").tag(2)
            }.pickerStyle(.segmented)
            Group {
                switch tab {
                case 0: video
                case 1: audio
                default: hud
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            Divider()
            HStack {
                Button("恢复默认") { draft = .init() }
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(model.running ? "保存并应用" : "保存设置") { model.apply(draft); dismiss() }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).disabled(model.pending)
            }
        }.padding(26).frame(width: 750, height: 650)
    }
    var video: some View {
        Form {
            Section {
                Picker("内部渲染分辨率", selection: $draft.scale) {
                    Text("1× · 480 × 272 · PSP 原始").tag(1)
                    Text("2× · 960 × 544 · 超过 480p 高度").tag(2)
                    Text("3× · 1440 × 816 · 超过 720p 高度").tag(3)
                    Text("4× · 1920 × 1088 · 接近 1080p").tag(4)
                }
                Text("PSP 使用 480∶272 比例。480p / 720p 指 480 / 720 条垂直像素；这里采用整数倍渲染，不等同于标准视频档位。窗口尺寸和 Retina 缩放另行决定显示大小。")
                    .font(.caption).foregroundStyle(.secondary)
                Text("当前 \(draft.resolution)，像素量为原始的 \(draft.scale * draft.scale) 倍。主要改善 3D 边缘；原始贴图与过场视频的细节不会同步增加。")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section {
                Toggle("垂直同步", isOn: $draft.vsync)
                Picker("纹理过滤", selection: $draft.textureFilter) {
                    Text("自动 · 遵循游戏").tag(1); Text("最近邻 · 锐利像素").tag(2)
                    Text("线性 · 平滑").tag(3); Text("自动 · 最高质量").tag(4)
                }
                Picker("各向异性过滤", selection: $draft.anisotropy) {
                    Text("关闭").tag(0); Text("2×").tag(1); Text("4×").tag(2); Text("8×").tag(3); Text("16×").tag(4)
                }
                Toggle("智能 2D 纹理过滤", isOn: $draft.smart2D)
                Picker("跳帧", selection: $draft.frameSkip) {
                    Text("关闭 · 推荐").tag(0); Text("跳过 1 帧").tag(1); Text("跳过 2 帧").tag(2)
                }
                Text("跳帧减少绘制量，但会降低画面连贯性。后端固定为 Vulkan → Metal。以上设置下次启动游戏时生效。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
    var audio: some View {
        Form {
            Section("立即应用") {
                Toggle("静音", isOn: $draft.muted)
                HStack {
                    Text("游戏音量")
                    Slider(value: Binding(get: { Double(draft.volume) }, set: { draft.volume = Int($0) }), in: 0...100, step: 1)
                    Text("\(draft.volume)%").monospacedDigit().frame(width: 45)
                }
            }
            Section("下次启动生效") {
                Picker("音频缓冲", selection: $draft.audioBuffer) {
                    Text("128 samples · 约 2.9 ms").tag(128)
                    Text("256 samples · 约 5.8 ms · 默认").tag(256)
                    Text("512 samples · 约 11.6 ms").tag(512)
                    Text("1024 samples · 约 23.2 ms").tag(1024)
                }
                Toggle("填补音频间隙", isOn: $draft.fillAudioGaps)
                Text("按 44.1 kHz 计算的单块缓冲时长，实际设备可能调整缓冲。较小缓冲可减少排队，较大缓冲更能容忍卡顿；若有爆音可提高一档。")
                    .font(.callout).foregroundStyle(.secondary)
                Text("这不是扬声器的实测延迟；蓝牙传输、混音与输出设备还会增加延迟。音频跟随 macOS 默认输出设备。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
    var hud: some View {
        Form {
            Section("游戏窗口右上角 · 立即应用") {
                Picker("显示内容", selection: $draft.hud) {
                    Text("关闭").tag(0); Text("简洁 · FPS / 速度").tag(1); Text("详细 · 加入帧间隔与分辨率").tag(2)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("FPS  60 / 60    SPEED  100%").font(.system(.headline, design: .monospaced))
                    if draft.hud == 2 {
                        Text("VBlank  16.7 ms   P95  17.2 ms\nRENDER  \(draft.resolution)").font(.system(.body, design: .monospaced))
                    }
                    Text("示意数据").font(.caption2)
                }.foregroundStyle(.green).padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 12)).opacity(draft.hud == 0 ? 0.25 : 1)
            }
            Section("如何理解指标") {
                Text("FPS：游戏实际呈现帧数 / 目标帧数。速度 100% 表示正常模拟速度；部分游戏本身以 30 FPS 运行。")
                Text("帧间隔：最近 60 次模拟 VBlank 的实测间隔，包含等待。P95 可帮助发现卡顿；它不是按键到屏幕的输入延迟。")
                Text("窗口被遮挡或放在后台时，macOS 可能限制呈现频率。后台数字不能代表前台游玩性能。")
            }.font(.callout).foregroundStyle(.secondary)
        }.formStyle(.grouped)
    }
}

struct DiagnosticsView: View {
    @ObservedObject var model: PlayerModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PanelHeader(title: "日志与调试", subtitle: "本机记录 · 导出不会包含 ROM 或存档内容")
            if !model.isPS2 { HStack(spacing: 12) {
                value("游戏帧率", model.status.map { String(format: "%.1f FPS", $0.game_fps) } ?? "—")
                value("VBlank 平均 / P95", model.status.flatMap { s in s.frame_ms_mean.map { String(format: "%.1f / %.1f ms", $0, s.frame_ms_p95 ?? 0) } } ?? "—")
                value("控制指令往返", model.lastCommandMilliseconds.map { String(format: "%.0f ms", $0) } ?? "未测量")
            }
            Text("指令往返包含本地文件通信与 300 ms 界面轮询。输入到屏幕延迟尚未测量。VBlank 统计含等待；后台呈现可能受系统限速影响。")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Label(model.status?.jit_active == true ? "ARM64 JIT 已启用" : "引擎未运行 / 尚未就绪", systemImage: "cpu")
                Spacer()
                Text(model.status.map { "\(PlayerPreferences.resolution($0.render_scale)) · RSS \(ByteCountFormatter.string(fromByteCount: Int64($0.rss_bytes), countStyle: .memory))" } ?? (model.isPS2 ? "ARMSX2 · 实时遥测尚未接入" : "Vulkan → MoltenVK → Metal"))
            }.font(.callout)
            } else {
                Text(model.running ? "ARMSX2 进程运行中 · FPS / 帧时间请查看游戏 HUD。" : "ARMSX2 尚未运行。")
                    .font(.callout).foregroundStyle(.secondary)
                Text("PS2 实时遥测与输入延迟尚未接入；此处提供引擎日志和诊断导出。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Text("引擎日志").font(.headline)
                Spacer()
                if !model.isPS2 { Button("测试控制响应") { model.command("ping") }.disabled(!model.ready || model.pending)
                Button("截取游戏画面") { model.captureGame() }.disabled(!model.ready || model.pending)
                }
                Button("刷新") { model.refreshLogs() }
            }
            ScrollView([.vertical, .horizontal]) {
                Text(model.logText).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading).padding(12)
            }.background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
            Text(model.sessionRoot.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(2)
            HStack {
                Button("打开日志目录") { model.reveal(model.sessionRoot) }
                Button("导出诊断报告…") { model.exportDiagnostics() }
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }.padding(26).frame(width: 830, height: 630).onAppear { model.refreshLogs() }
    }
    func value(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(text).font(.system(size: 20, weight: .medium, design: .rounded)).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading).padding(14).background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }
}

struct PlayerCommands: Commands {
    @ObservedObject var model: PlayerModel
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("添加本地游戏…") { model.chooseFiles() }.keyboardShortcut("o").disabled(model.running)
            Button("从游戏库移除") { model.removeSelected() }.disabled(model.running || model.selected == nil)
        }
        CommandGroup(replacing: .appSettings) { Button("播放设置…") { model.present(model.isPS2 ? .ps2 : .settings) }.keyboardShortcut(",") }
        UnusedCommands()
        CommandGroup(replacing: .help) { Button("键盘与手柄示意图…") { model.present(.controls) }.keyboardShortcut("/", modifiers: [.command]) }
        CommandMenu("游戏") {
            Button("开始游戏") { model.start() }.disabled(model.running || model.selected == nil)
            if !model.isPS2 { Button("继续自动存档") { model.start(resume: true) }.disabled(model.isPS2 || model.running || model.selected?.autoState == nil)
            }
            Button("回到游戏窗口") { model.focusGame() }.disabled(!model.running)
            Divider()
            if !model.isPS2 { Button(model.status?.playing == false ? "继续" : "暂停") { model.command("pause") }.keyboardShortcut("p").disabled(!model.ready || model.pending)
            Button("保存手动存档") { model.command("save 1") }.keyboardShortcut("s").disabled(!model.ready || model.pending)
            Button("读取手动存档") { model.command("load 1") }.keyboardShortcut("l").disabled(!model.ready || model.pending || model.status?.manual_exists != true)
            }
            Button(model.isPS2 ? "结束 ARMSX2" : "保存并结束游戏") { model.command("quit") }.disabled(!model.running || model.pending)
        }
        CommandMenu("诊断") {
            Button("日志与调试…") { model.present(.diagnostics) }.keyboardShortcut("d", modifiers: [.command, .shift])
            Button("导出诊断报告…") { model.exportDiagnostics() }
            Button("游戏库与存档目录") { model.revealData() }
        }
    }
}

struct UnusedCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .saveItem) { }
        CommandGroup(replacing: .printItem) { }
        CommandGroup(replacing: .undoRedo) { }
        CommandGroup(replacing: .textEditing) { }
        CommandGroup(replacing: .toolbar) { }
        CommandGroup(replacing: .sidebar) { }
    }
}
