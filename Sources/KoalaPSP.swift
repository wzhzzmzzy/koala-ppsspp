import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct EngineStatus: Decodable {
    var ready: Bool
    var playing: Bool
    var game_fps: Double
    var speed_percent: Double
    var rss_bytes: UInt64
    var jit_active: Bool
    var render_scale: Int
    var muted: Bool
    var saving: Bool
    var title: String
    var auto_exists: Bool
    var manual_exists: Bool
    var auto_path: String
    var frame_ms_mean: Double?
    var frame_ms_p95: Double?
    var frame_samples: Int?
    var volume: Int?
    var hud: Int?
    var audio_buffer: Int?
    var vsync: Bool?
    var texture_filter: Int?
    var anisotropy: Int?
}
enum PlayerPanel: String, Identifiable { case settings, controls, diagnostics; var id: String { rawValue } }

struct CommandAck: Decodable { var id: String; var ok: Bool; var message: String }

@MainActor final class PlayerModel: ObservableObject {
    static let shared = PlayerModel()
    @Published var games: [Game] = []
    @Published var selection: String? { didSet { persistState() } }
    @Published var running = false
    @Published var status: EngineStatus?
    @Published var feedback = "选择本机游戏，开始游玩。"
    @Published var error: String?
    @Published var preferences = PlayerPreferences()
    @Published var panel: PlayerPanel?
    @Published var mappings: MappingSnapshot?
    @Published var mappingSource = "尚未读取按键配置"
    private var lastMappingData: Data?

    @Published var logText = "尚无引擎日志。"
    @Published var lastCommandMilliseconds: Double?
    @Published var needsRestart = false
    var scale: Int {
        get { preferences.scale }
        set { preferences.scale = min(4, max(1, newValue)); persistPreferences() }
    }
    @Published var pending = false
    let store: LocalStore
    var dataRoot: URL { store.paths.data }
    var controlRoot: URL
    private(set) var sessionRoot: URL
    private var loaded = false
    private var libraryState = LibraryState()
    private var process: Process?
    private var timer: Timer?
    private var pendingID: String?
    private var pendingAt = Date()
    private var activeID: String?
    private var logHandle: FileHandle?
    private var quitCompletion: (() -> Void)?

    var selected: Game? { games.first { $0.id == selection } }
    var ready: Bool { running && status?.ready == true }

    init() {
        let env = ProcessInfo.processInfo.environment
        store = LocalStore(paths: AppPaths(environment: env))
        controlRoot = store.paths.runtime
        sessionRoot = store.paths.state
        do {
            try store.paths.prepare()
            try store.migrateLegacy()
            games = try store.read([Game].self, from: store.libraryURL, fallback: [])
            preferences = try store.read(PlayerPreferences.self, from: store.preferencesURL, fallback: .init())
            libraryState = try store.read(LibraryState.self, from: store.stateURL, fallback: .init())
            if let latest = try? FileManager.default.contentsOfDirectory(at: store.paths.state.appendingPathComponent("sessions"), includingPropertiesForKeys: [.contentModificationDateKey]).sorted(by: {
                ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) >
                ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
            }).first { sessionRoot = latest }
            selection = games.contains(where: { $0.id == libraryState.selectedGameID }) ? libraryState.selectedGameID : games.first?.id
            loaded = true
        } catch { self.error = error.localizedDescription }
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    func persistLibrary() {
        guard loaded else { return }
        do { try store.write(games, to: store.libraryURL) }
        catch { self.error = "游戏库保存失败：\(error.localizedDescription)" }
    }

    func persistPreferences() {
        guard loaded else { return }
        do { try store.write(preferences, to: store.preferencesURL) }
        catch { self.error = "设置保存失败：\(error.localizedDescription)" }
    }
    func persistState() {
        guard loaded else { return }
        libraryState.selectedGameID = selection
        do { try store.write(libraryState, to: store.stateURL) }
        catch { self.error = "本地状态保存失败：\(error.localizedDescription)" }
    }

    func addFile(_ url: URL) {
        guard loaded else { return }
        guard ["iso", "cso", "chd", "pbp", "elf"].contains(url.pathExtension.lowercased()) else {
            error = "请选择 ISO、CSO、CHD、PBP 或 ELF 游戏文件。"; return
        }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular else { error = "请选择游戏文件。"; return }
            if let existing = games.first(where: { $0.path == url.path }) { selection = existing.id; return }
            let game = Game(id: UUID().uuidString, path: url.path, title: url.deletingPathExtension().lastPathComponent,
                            bytes: (attributes[.size] as? NSNumber)?.int64Value ?? 0)
            games.append(game); selection = game.id; persistLibrary()
            feedback = "已添加游戏。原文件保留在当前位置。"
        } catch { self.error = "无法读取文件：\(error.localizedDescription)" }
    }

    func chooseFiles() {
        let picker = NSOpenPanel()
        picker.title = "添加 PSP 游戏"
        picker.prompt = "添加到游戏库"
        picker.allowsMultipleSelection = true
        picker.canChooseDirectories = false
        picker.allowedContentTypes = ["iso", "cso", "chd", "pbp", "elf"].compactMap { UTType(filenameExtension: $0) }
        if picker.runModal() == .OK { for file in picker.urls { addFile(file) } }
    }

    func removeSelected() {
        guard !running, let id = selection else { return }
        games.removeAll { $0.id == id }; selection = games.first?.id; persistLibrary()
        feedback = "已从游戏库移除，原文件与存档仍保留。"
    }

    func start(resume: Bool = false) {
        guard loaded, !running, let game = selected else { return }
        guard FileManager.default.isReadableFile(atPath: game.path) else { error = "找不到游戏文件，请重新添加。"; return }
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/PPSSPPSDL.app/Contents/MacOS/PPSSPPSDL")
        guard FileManager.default.isExecutableFile(atPath: helper.path) else { error = "原生引擎缺失，请重新构建应用。"; return }
        do {
            let configuredControl = ProcessInfo.processInfo.environment["KOALA_CONTROL_DIR"]
            let sessionID = UUID().uuidString
            controlRoot = configuredControl.map { URL(fileURLWithPath: $0, isDirectory: true) }
                ?? store.paths.runtime.appendingPathComponent(sessionID, isDirectory: true)
            sessionRoot = store.paths.state.appendingPathComponent("sessions/\(sessionID)", isDirectory: true)
            for directory in [controlRoot, sessionRoot] {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            }
            let configURL = controlRoot.appendingPathComponent("launch.ini")
            let config = preferences.launchConfig
            try config.write(to: configURL, atomically: true, encoding: .utf8)
            let child = Process()
            child.executableURL = helper
            child.currentDirectoryURL = helper.deletingLastPathComponent()
            child.arguments = [game.path, "--appendconfig=\(configURL.path)", "--windowed", "--xres", "960", "--yres", "544", "--pause-menu-exit"]
            if resume, let path = game.autoState, FileManager.default.fileExists(atPath: path) { child.arguments?.append("--state=\(path)") }
            var environment = ProcessInfo.processInfo.environment
            environment["KOALA_DATA_DIR"] = dataRoot.path
            environment["KOALA_CONFIG_DIR"] = store.paths.engineConfig.path
            environment["KOALA_CACHE_DIR"] = store.paths.cache.path
            environment["KOALA_LOG_DIR"] = sessionRoot.path
            environment["KOALA_CONTROL_DIR"] = controlRoot.path
            child.environment = environment
            let logURL = sessionRoot.appendingPathComponent("engine.log")
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
            logHandle = try FileHandle(forWritingTo: logURL)
            child.standardOutput = logHandle; child.standardError = logHandle
            child.terminationHandler = { [weak self] child in
                Task { @MainActor in
                    guard let self else { return }
                    self.poll()
                    self.running = false; self.pending = false; self.process = nil; self.status = nil
                    try? self.logHandle?.close(); self.logHandle = nil
                    if configuredControl == nil { try? FileManager.default.removeItem(at: self.controlRoot) }
                    if child.terminationStatus != 0 { self.error = "引擎已退出（\(child.terminationStatus)），请在“日志与调试”中查看原因。" }
                    else { self.feedback = "游戏已结束。" }
                    self.quitCompletion?(); self.quitCompletion = nil
                }
            }
            try child.run()
            mappings = nil; lastMappingData = nil
            process = child; running = true; status = nil; activeID = game.id; needsRestart = false
            libraryState.lastPlayedGameID = game.id; libraryState.lastPlayedAt = Date(); persistState()
            if let index = games.firstIndex(where: { $0.id == game.id }) { games[index].lastPlayed = Date(); persistLibrary() }
            feedback = "正在打开原生游戏窗口…"
            try String(child.processIdentifier).write(to: controlRoot.appendingPathComponent("engine.pid"), atomically: true, encoding: .utf8)
        } catch { self.error = "启动失败：\(error.localizedDescription)" }
    }

    func command(_ operation: String) {
        guard running else { return }
        guard !pending else { error = "请等待上一项操作完成。"; return }
        let id = UUID().uuidString
        do {
            try "\(id) \(operation)\n".write(to: controlRoot.appendingPathComponent("command.txt"), atomically: true, encoding: .utf8)
            pendingID = id; pendingAt = Date(); pending = true
        } catch { self.error = "操作失败：\(error.localizedDescription)" }
    }

    func poll() {
        if panel == .diagnostics { refreshLogs() }
        if panel == .controls { refreshMappings() }
        guard running else { return }
        let requestURL = controlRoot.appendingPathComponent("ui-request.txt")
        if let request = try? String(contentsOf: requestURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines) {
            try? FileManager.default.removeItem(at: requestURL)
            if let requestedPanel = PlayerPanel(rawValue: request) { present(requestedPanel) }
            else if request == "library" { NSApp.activate(ignoringOtherApps: true) }
            else if request == "hud" { var p = preferences; p.hud = p.hud == 0 ? 2 : 0; apply(p) }
            else if ["pause", "mute", "save 1", "load 1", "quit"].contains(request) { command(request) }
        }
        if let data = try? Data(contentsOf: controlRoot.appendingPathComponent("status.json")),
           let next = try? JSONDecoder().decode(EngineStatus.self, from: data) {
            if next.ready && status?.ready != true {
                feedback = "游戏已就绪，可回到游戏窗口游玩。"
            }
            if !pending && preferences.muted != next.muted { preferences.muted = next.muted; persistPreferences() }
            status = next
            if let index = games.firstIndex(where: { $0.id == activeID }) {
                var changed = false
                if !next.title.isEmpty && games[index].title != next.title { games[index].title = next.title; changed = true }
                if !next.auto_path.isEmpty && games[index].autoState != next.auto_path { games[index].autoState = next.auto_path; changed = true }
                if changed { persistLibrary() }
            }
        }
        if pending, let data = try? Data(contentsOf: controlRoot.appendingPathComponent("ack.json")),
           let ack = try? JSONDecoder().decode(CommandAck.self, from: data), ack.id == pendingID {
            lastCommandMilliseconds = Date().timeIntervalSince(pendingAt) * 1_000
            pending = false; pendingID = nil; feedback = ack.message
            if !ack.ok { error = ack.message; quitCompletion = nil; NSApp.reply(toApplicationShouldTerminate: false) }
        }
        if pending && Date().timeIntervalSince(pendingAt) > 15 {
            pending = false; pendingID = nil; error = "引擎未及时响应，现有存档已保留。"
            if quitCompletion != nil { quitCompletion = nil; NSApp.reply(toApplicationShouldTerminate: false) }
        }
    }

    func refreshMappings() {
        let url = running ? controlRoot.appendingPathComponent("mappings.json") : store.paths.engineConfig.appendingPathComponent("controls.ini")
        do {
            if running {
                let changed = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
                guard Date().timeIntervalSince(changed) < 4 else { mappingSource = "实时连接中断 · 显示最后快照"; return }
            }
            let data = try Data(contentsOf: url)
            if data != lastMappingData {
                mappings = try running ? JSONDecoder().decode(MappingSnapshot.self, from: data) : MappingSnapshot.savedINI(String(decoding: data, as: UTF8.self))
                lastMappingData = data
            }
            mappingSource = running ? "模拟器实时配置 · 自动同步（含游戏专属配置）" : "已保存的全局配置 · 游戏专属配置启动后同步"
        } catch {
            mappings = nil; lastMappingData = nil
            mappingSource = FileManager.default.fileExists(atPath: url.path) ? "读取按键配置失败：\(error.localizedDescription)" : running ? "等待模拟器按键配置…" : "尚无已保存配置 · 请先启动一次游戏"
        }
    }
    func editMappings() { guard ready, !pending else { return }; command("mapping-ui"); focusGame() }

    func apply(_ draft: PlayerPreferences) {
        var next = draft; next.normalize()
        var oldRestart = preferences; oldRestart.muted = next.muted; oldRestart.volume = next.volume; oldRestart.hud = next.hud
        needsRestart = running && (needsRestart || oldRestart != next)
        preferences = next; persistPreferences()
        if ready { command(next.liveCommand) }
        else { feedback = "设置已保存，下次启动游戏时生效。" }
    }
    func present(_ pane: PlayerPanel) {
        panel = pane
        if pane == .diagnostics { refreshLogs() }
        if pane == .controls { refreshMappings() }
        // Only called from an explicit toolbar/menu action.
        NSApp.activate(ignoringOtherApps: true)
    }
    func refreshLogs() {
        let url = sessionRoot.appendingPathComponent("engine.log")
        guard let file = try? FileHandle(forReadingFrom: url) else { logText = "尚无引擎日志。启动游戏后自动记录。"; return }
        defer { try? file.close() }
        do {
            let size = try file.seekToEnd(); try file.seek(toOffset: size > 65_536 ? size - 65_536 : 0)
            logText = String(decoding: try file.readToEnd() ?? Data(), as: UTF8.self)
            if size > 65_536 { logText = "[仅显示日志末尾 64 KiB]\n" + logText }
        } catch { logText = "读取日志失败：\(error.localizedDescription)" }
    }
    func diagnosticData() throws -> Data {
        refreshLogs()
        var safeLog = logText.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
        for game in games { safeLog = safeLog.replacingOccurrences(of: game.path, with: "<game-file>") }
        var report: [String: Any] = ["appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "development",
            "system": ProcessInfo.processInfo.operatingSystemVersionString, "architecture": "arm64",
            "engine": "PPSSPP 1.20.4 / Vulkan → MoltenVK → Metal", "running": running,
            "preferences": try JSONSerialization.jsonObject(with: JSONEncoder().encode(preferences)),
            "logTail": safeLog, "inputToPhotonLatency": "not measured",
            "frameTimingDefinition": "Most recent 60 emulated VBlank intervals, including waits; not input latency",
            "exportedAt": ISO8601DateFormatter().string(from: Date())]
        if let data = try? Data(contentsOf: controlRoot.appendingPathComponent("status.json")),
           var status = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            status.removeValue(forKey: "auto_path"); report["status"] = status
        }
        if let latency = lastCommandMilliseconds { report["lastCommandRoundTripMS"] = latency }
        return try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    }
    func exportDiagnostics() {
        let picker = NSSavePanel(); picker.nameFieldStringValue = "Koala-PSP-diagnostics.json"; picker.allowedContentTypes = [.json]
        if picker.runModal() == .OK, let url = picker.url {
            do { try diagnosticData().write(to: url, options: .atomic); feedback = "诊断报告已导出。" }
            catch { self.error = "导出失败：\(error.localizedDescription)" }
        }
    }
    func captureGame() { command("screenshot capture-\(Int(Date().timeIntervalSince1970)).png") }

    func requestQuit(_ completion: @escaping () -> Void) {
        guard running else { completion(); return }
        guard !pending else { error = "请等待当前存档操作结束后退出。"; NSApp.reply(toApplicationShouldTerminate: false); return }
        quitCompletion = completion; command("quit")
    }
    func revealData() { NSWorkspace.shared.open(dataRoot) }
    func reveal(_ directory: URL) { NSWorkspace.shared.open(directory) }
    func focusGame() {
        if let pid = process?.processIdentifier { NSRunningApplication(processIdentifier: pid)?.activate(options: [.activateAllWindows]) }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if !PlayerModel.shared.running { return .terminateNow }
        PlayerModel.shared.requestQuit { NSApp.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
}

struct PlayerView: View {
    @ObservedObject var model: PlayerModel
    @State private var handledArguments = false
    private let tint = Color(red: 0.92, green: 0.49, blue: 0.22)
    var body: some View {
        NavigationSplitView {
            List(selection: $model.selection) {
                Section("PSP 游戏库") {
                    ForEach(model.games) { game in
                        Label(game.title, systemImage: "gamecontroller").tag(game.id).padding(.vertical, 6)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 240)
            .safeAreaInset(edge: .bottom) {
                Button { model.chooseFiles() } label: { Label("添加本地游戏", systemImage: "plus") }
                    .buttonStyle(.borderless).padding(16).frame(maxWidth: .infinity, alignment: .leading)
            }
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(alignment: .center, spacing: 20) {
                        Image(systemName: "gamecontroller.fill").font(.system(size: 58)).foregroundStyle(tint)
                            .frame(width: 118, height: 104).background(.quaternary, in: RoundedRectangle(cornerRadius: 20))
                        VStack(alignment: .leading, spacing: 8) {
                            Text(model.selected?.title ?? "你的掌上游戏库").font(.system(size: 26, weight: .semibold)).lineLimit(3)
                            Text(model.selected.map { ByteCountFormatter.string(fromByteCount: $0.bytes, countStyle: .file) + " · 本机文件" } ?? "将 PSP 游戏添加到这里，随时继续冒险。")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    if model.running {
                        HStack {
                            Button { model.focusGame() } label: { Label("回到游戏", systemImage: "play.fill") }.buttonStyle(.borderedProminent)
                            Button(model.status?.playing == false ? "继续" : "暂停") { model.command("pause") }.disabled(!model.ready || model.pending)
                            Button(model.status?.muted == true ? "开启声音" : "静音") { model.command("mute") }.disabled(!model.ready || model.pending)
                            Button("全屏") { model.command("fullscreen") }.disabled(!model.ready || model.pending)
                            Spacer()
                            Button("保存并结束") { model.command("quit") }.disabled(model.pending)
                        }
                    } else {
                        HStack(spacing: 12) {
                            Button { model.start() } label: { Label("开始游戏", systemImage: "play.fill").padding(.horizontal, 10) }
                                .buttonStyle(.borderedProminent).disabled(model.selected == nil)
                            Button("继续自动存档") { model.start(resume: true) }.disabled(model.selected?.autoState == nil)
                            Spacer()
                            Button { model.present(.settings) } label: {
                                Label(model.preferences.graphicsDescription, systemImage: "slider.horizontal.3")
                            }.help("渲染分辨率、视频、音频与 HUD 设置")
                        }
                    }
                    if let status = model.status, model.running {
                        HStack(spacing: 12) {
                            metric("游戏帧率", String(format: "%.1f FPS", status.game_fps))
                            metric("运行速度", String(format: "%.0f%%", status.speed_percent))
                            metric("驻留内存（RSS）", ByteCountFormatter.string(fromByteCount: Int64(status.rss_bytes), countStyle: .memory))
                        }
                    }
                    GroupBox {
                        VStack(spacing: 0) {
                            slot("自动存档", subtitle: "每 30 秒保存，结束游戏时再保存", slot: 0, exists: model.status?.auto_exists == true)
                            Divider().padding(.vertical, 12)
                            slot("手动存档", subtitle: "保存你想回到的时刻", slot: 1, exists: model.status?.manual_exists == true)
                        }.padding(12)
                    } label: { Text("游戏进度").font(.headline) }
                    GroupBox {
                        HStack(spacing: 20) {
                            Image(systemName: "keyboard").font(.system(size: 30)).foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("键盘与手柄").font(.headline)
                                Text("查看按键位置、PSP 对应关系和常用快捷键。").foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("查看示意图…") { model.present(.controls) }
                        }.padding(12)
                    }
                    if model.needsRestart {
                        Label("画面与缓冲设置将在下次启动游戏时生效。", systemImage: "arrow.clockwise").font(.callout).foregroundStyle(.orange)
                    }
                    HStack {
                        if model.pending { ProgressView().controlSize(.small) }
                        Text(model.feedback).font(.callout).foregroundStyle(.secondary)
                        Spacer()
                    }
                    Text("游戏直接读取本机文件。存档只保存在这台 Mac。").font(.caption).foregroundStyle(.tertiary)
                }.padding(30).frame(maxWidth: 920)
            }
            .navigationTitle("Koala PSP")
            .toolbar {
                ToolbarItem {
                    Button { model.chooseFiles() } label: { Label("添加游戏", systemImage: "plus").labelStyle(.titleAndIcon) }
                        .keyboardShortcut("o").help("添加本机 ISO / CSO / CHD 等游戏文件（⌘O），保留原文件位置")
                }
                ToolbarItem { Button { model.present(.settings) } label: { Label("设置", systemImage: "slider.horizontal.3") }.help("视频、音频与性能 HUD（⌘,）") }
                ToolbarItem { Button { model.present(.diagnostics) } label: { Label("日志与调试", systemImage: "waveform.path.ecg") } }
                ToolbarItem {
                    Menu {
                        Button("游戏库与存档") { model.revealData() }.help(model.store.paths.data.path)
                        Button("偏好设置与按键配置") { model.reveal(model.store.paths.config) }.help(model.store.paths.config.path)
                        Button("运行状态与日志") { model.reveal(model.store.paths.state) }.help(model.store.paths.state.path)
                        Button("可重建缓存") { model.reveal(model.store.paths.cache) }.help(model.store.paths.cache.path)
                    } label: { Label("本地文件", systemImage: "folder").labelStyle(.titleAndIcon) }
                    .help("在 Finder 中打开对应的 XDG 本地目录")
                }
            }
        }
        .tint(tint)
        .frame(minWidth: 900, minHeight: 680)
        .alert("未能完成操作", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("好", role: .cancel) { model.error = nil }
        } message: { Text(model.error ?? "") }
        .sheet(item: $model.panel) { panel in
            switch panel {
            case .settings: PlayerSettingsView(model: model)
            case .controls: ControlsView()
            case .diagnostics: DiagnosticsView(model: model)
            }
        }
        .onAppear {
            guard !handledArguments else { return }; handledArguments = true
            let args = CommandLine.arguments
            if let i = args.firstIndex(of: "--scale"), args.indices.contains(i + 1) { model.scale = min(4, max(1, Int(args[i + 1]) ?? 1)) }
            if let i = args.firstIndex(of: "--rom"), args.indices.contains(i + 1) { model.addFile(URL(fileURLWithPath: args[i + 1])) }
            if args.contains("--play") { model.start(resume: args.contains("--resume")) }
        }
    }

    func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 24, weight: .medium, design: .rounded)).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16).background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }
    func slot(_ name: String, subtitle: String, slot: Int, exists: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) { Text(name).fontWeight(.medium); Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            Spacer()
            Button("保存") { model.command("save \(slot)") }.disabled(!model.ready || model.pending || model.status?.saving == true)
            Button("读取") { model.command("load \(slot)") }.disabled(!model.ready || model.pending || !exists)
        }
    }
}

@main struct KoalaPSPApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    init() {
        if let i = CommandLine.arguments.firstIndex(of: "--mapping-report"), CommandLine.arguments.indices.contains(i + 1) {
            do {
                let model = PlayerModel.shared
                model.controlRoot = URL(fileURLWithPath: CommandLine.arguments[i + 1]).deletingLastPathComponent()
                model.running = true; model.refreshMappings()
                guard let snapshot = model.mappings else { throw MappingError.invalid(model.mappingSource) }
                var report = Dictionary(uniqueKeysWithValues: PadPart.allCases.map { ($0.rawValue, snapshot.summary(codes: $0.codes, device: 10)) })
                report["_source"] = model.mappingSource
                FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])); exit(0)
            } catch { fputs("Mapping check failed: \(error)\n", stderr); exit(1) }
        }
        if let i = CommandLine.arguments.firstIndex(of: "--render-previews"), CommandLine.arguments.indices.contains(i + 1) {
            do { try renderPreviews(to: URL(fileURLWithPath: CommandLine.arguments[i + 1])); exit(0) }
            catch { fputs("Preview failed: \(error)\n", stderr); exit(1) }
        }
        if CommandLine.arguments.contains("--launch-config") {
            do {
                let store = LocalStore(paths: AppPaths())
                let p = try store.read(PlayerPreferences.self, from: store.preferencesURL, fallback: .init())
                print(p.launchConfig); exit(0)
            } catch { fputs("Config check failed: \(error)\n", stderr); exit(1) }
        }
        // A background-only packaging/storage probe: exits before creating UI.
        if CommandLine.arguments.contains("--storage-report") {
            do {
                let store = LocalStore(paths: AppPaths())
                try store.paths.prepare(); try store.migrateLegacy()
                let games = try store.read([Game].self, from: store.libraryURL, fallback: [])
                let preferences = try store.read(PlayerPreferences.self, from: store.preferencesURL, fallback: .init())
                let state = try store.read(LibraryState.self, from: store.stateURL, fallback: .init())
                let report: [String: Any] = ["data":store.paths.data.path, "config":store.paths.config.path,
                    "state":store.paths.state.path, "cache":store.paths.cache.path, "runtime":store.paths.runtime.path,
                    "games":games.count, "scale":preferences.scale, "muted":preferences.muted,
                    "selection":state.selectedGameID ?? "", "iconPresent":Bundle.main.url(forResource:"AppIcon", withExtension:"icns") != nil]
                FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]))
                exit(0)
            } catch { fputs("Storage check failed: \(error)\n", stderr); exit(1) }
        }
    }
    var body: some Scene {
        Window("Koala PSP", id: "library") { PlayerView(model: .shared) }
            .commands { PlayerCommands(model: .shared) }
    }
}
