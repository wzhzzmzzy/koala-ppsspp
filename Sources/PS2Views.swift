import SwiftUI

struct PS2LibrarySection: View {
    @ObservedObject var model: PlayerModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("ARMSX2 · 原生 ARM64", systemImage: "cpu").font(.headline)
                Spacer()
                Text("PS2 预览版").font(.caption).padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.orange.opacity(0.15), in: Capsule())
            }
            if model.running {
                HStack {
                    Button("回到 ARMSX2") { model.focusGame() }.buttonStyle(.borderedProminent)
                    Spacer()
                    Button("结束引擎") { model.command("quit") }.disabled(model.pending)
                }
                Text("暂停、即时存档和改键使用引擎菜单。FPS、速度与帧时间在游戏 HUD 内显示；启动器暂不接收 PS2 实时遥测。")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                HStack {
                    Button { model.start() } label: { Label("开始 PS2 游戏", systemImage: "play.fill") }
                        .buttonStyle(.borderedProminent).disabled(model.selected == nil)
                    Button("PS2 设置…") { model.present(.ps2) }
                }
            }
            GroupBox {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "cpu").font(.system(size: 28)).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.biosDescription).fontWeight(.medium)
                        Text("BIOS 是 PS2 的启动程序，与游戏镜像分开。导入自己的 BIOS 后即可尝试启动。")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("导入 BIOS…") { model.importPS2BIOS() }.disabled(model.running)
                }.padding(10)
            }
            Text("游戏内进度写入 PS2 记忆卡。即时存档由 ARMSX2 管理，与 PSP 存档分开。尚未验证商业游戏游玩和性能。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct PS2SettingsView: View {
    @ObservedObject var model: PlayerModel
    @Environment(\.dismiss) private var dismiss
    @State private var options: PS2Options
    init(model: PlayerModel) {
        self.model = model
        _options = State(initialValue: PS2Options((try? model.ps2.read()) ?? EngineINI("")))
    }
    var body: some View {
        VStack(spacing: 18) {
            PanelHeader(title: "PS2 设置", subtitle: "ARMSX2 \(PS2Engine.version) · 原生 ARM64 引擎")
            Form {
                Section("主机 BIOS") {
                    HStack {
                        Text(model.biosDescription)
                        Spacer()
                        Button("导入 BIOS…") { model.importPS2BIOS() }.disabled(model.running)
                        Button("启动系统菜单") { dismiss(); model.startPS2(.bios) }.disabled(model.running)
                    }
                    Text("BIOS 是主机内置的启动程序，不是游戏，也不是模拟器。请从自己的 PS2 提取；导入时检查文件结构并复制到本地目录，保留原件。应用不附带 BIOS。")
                        .font(.caption).foregroundStyle(.secondary)
                    Link("查看 BIOS 提取指南 ↗", destination: URL(string: "https://pcsx2.net/docs/setup/bios/")!)
                }
                Section("画面、声音与 HUD · 保存后下次启动生效") {
                    Picker("内部渲染倍率", selection: $options.scale) {
                        Text("1× · 原始分辨率").tag(1)
                        Text("2× · 例：1280 × 896").tag(2)
                        Text("3× · 例：1920 × 1344").tag(3)
                        Text("4× · 例：2560 × 1792").tag(4)
                    }
                    Text("PS2 游戏分辨率不同；以上以 640 × 448 为例，不能固定称为 720p 或 1080p。实际内部尺寸请查看游戏 HUD。默认使用 Metal；高级设置可切换渲染器。")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Text("游戏音量")
                        Slider(value: Binding(get: { Double(options.volume) }, set: { options.volume = Int($0) }), in: 0...100, step: 1)
                        Text("\(options.volume)%").monospacedDigit().frame(width: 46)
                    }
                    Toggle("显示 FPS、速度、分辨率和帧时间 HUD", isOn: $options.hud)
                    Text("帧时间不是按键到屏幕的延迟。后台运行可能被 macOS 限速，不能代表前台性能。")
                        .font(.caption).foregroundStyle(.secondary)
                }.disabled(model.running)
                Section("高级控制") {
                    HStack {
                        Text("改键、手柄自动映射、纹理、去隔行与音频缓冲")
                        Spacer()
                        Button(model.running ? "回到 ARMSX2" : "打开原生引擎设置…") {
                            dismiss()
                            if model.running { model.focusGame() } else { model.startPS2(.settings) }
                        }
                    }
                    Text("在 ARMSX2 的 Settings 菜单中调整。这里读取引擎保存的全局按键配置；游戏专属配置可能覆盖它。修改后关闭引擎即可返回游戏库启动。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped)
            HStack {
                Menu("本地目录") {
                    Button("BIOS 与记忆卡") { model.reveal(model.ps2.data) }
                    Button("PS2 配置") { model.reveal(model.ps2.config) }
                }.fixedSize()
                Text(model.running ? "引擎运行中，使用原生设置修改。" : "与 ARMSX2 共用配置。")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存设置") {
                    do { try model.ps2.apply(options); model.feedback = "PS2 设置已保存，下次启动生效。"; dismiss() }
                    catch { model.error = error.localizedDescription }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(model.running)
            }
        }.padding(26).frame(width: 810, height: 730)
    }
}
