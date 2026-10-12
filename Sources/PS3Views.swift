import SwiftUI

struct PS3LibrarySection: View {
    @ObservedObject var model: PlayerModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("RPCS3 · 官方 ARM64", systemImage: "cpu").font(.headline)
                Spacer()
                Text("PS3 接入预览").font(.caption).padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.orange.opacity(0.15), in: Capsule())
            }
            if !PS3Engine.supported {
                Label("PS3 需要 macOS 15 或更新版本。", systemImage: "info.circle").foregroundStyle(.orange)
            }
            if model.running {
                HStack {
                    Button("回到 RPCS3") { model.focusGame() }.buttonStyle(.borderedProminent)
                    Spacer()
                    Button("请求退出 RPCS3") { model.stopPS3() }.disabled(model.pending)
                }
                Text("暂停、存档、画质和输入使用 RPCS3 原生窗口。关闭 RPCS3 后可在这里切换游戏。")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                HStack {
                    Button { model.start() } label: { Label("开始 PS3 游戏", systemImage: "play.fill") }
                        .buttonStyle(.borderedProminent).disabled(model.selected == nil || !PS3Engine.supported)
                    Button("PS3 设置…") { model.present(.ps3) }
                    Spacer()
                    Button("扫描已安装游戏") { model.scanPS3Games() }
                }
            }
            GroupBox {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "internaldrive").font(.system(size: 28)).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.firmwareDescription).fontWeight(.medium)
                        Text("首次使用：下载 Sony 的 PS3 系统软件，再交给 RPCS3 安装。游戏文件夹与 ISO 可直接添加，PKG 需要先安装。")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("安装固件…") { model.installPS3(firmware: true) }.disabled(model.running || !PS3Engine.supported)
                }.padding(10)
            }
            Text("第一版共用 RPCS3 标准数据目录；Koala PS 不改写已有配置。游戏兼容性和帧率尚未在本机验证。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct PS3SettingsView: View {
    @ObservedObject var model: PlayerModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 18) {
            PanelHeader(title: "PS3 设置", subtitle: "RPCS3 \(PS3Engine.version) · 官方 ARM64 · macOS 15+")
            Form {
                Section("系统软件与游戏") {
                    Text(model.firmwareDescription)
                    HStack {
                        Link("下载 Sony 官方固件 ↗", destination: PS3Engine.firmwareURL)
                        Spacer()
                        Button("安装 PS3UPDAT.PUP…") { dismiss(); model.installPS3(firmware: true) }
                            .disabled(model.running || !PS3Engine.supported)
                    }
                    HStack {
                        Text("游戏 / 更新安装包")
                        Spacer()
                        Button("安装 PKG…") { dismiss(); model.installPS3(firmware: false) }
                            .disabled(model.running || !PS3Engine.supported)
                    }
                    Text("安装完成后关闭 RPCS3，Koala PS 会刷新固件状态和游戏列表。光盘文件夹或 ISO 使用「添加游戏」；游戏许可证在 RPCS3 中导入。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("画面、音频、HUD 与输入") {
                    Text("本阶段由 RPCS3 的 Settings 和 Pads 管理，包括每个游戏的专属设置。Koala PS 暂不覆盖键盘或手柄映射。")
                    HStack {
                        Text("使用官方内置 MoltenVK 图形驱动")
                        Spacer()
                        Button(model.running ? "回到 RPCS3" : "打开 RPCS3…") {
                            dismiss()
                            if model.running { model.focusGame() } else { model.startPS3(.library) }
                        }.disabled(!PS3Engine.supported)
                    }
                    Text("PSP 的 KosmicKrisp 选项不应用到 PS3。FPS / 帧时间可在 RPCS3 的性能叠层中查看，启动器尚未接收实时遥测。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("本地数据") {
                    Text("与独立安装的 RPCS3 共用标准目录，请勿同时运行两个实例。Koala PS 的游戏列表和会话日志仍使用 XDG 目录。")
                        .font(.callout)
                    Text(model.ps3.config.path).font(.caption).textSelection(.enabled)
                    HStack {
                        Button("配置、固件与存档") { model.reveal(model.ps3.config) }
                        Button("原生日志与缓存") { model.reveal(model.ps3.cache) }
                        Button("扫描已安装游戏") { model.scanPS3Games() }.disabled(model.running)
                    }
                    Text("若在 RPCS3 的 VFS 设置中改过磁盘路径，固件检测和游戏扫描会读取该配置。这里不移动或重写原有数据。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped)
            HStack {
                Text("原生设置由 RPCS3 自行保存。").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }.padding(26).frame(width: 810, height: 760).onAppear { model.refreshPS3() }
    }
}

struct PS3ControlsView: View {
    @ObservedObject var model: PlayerModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PanelHeader(title: "PS3 键盘与手柄", subtitle: "当前映射由 RPCS3 管理")
            Label("打开 RPCS3 后，点击工具栏的 Pads。", systemImage: "gamecontroller").font(.headline)
            Text("选择玩家和输入设备，配置键盘或连接的手柄，保存输入配置。游戏专属设置可能覆盖全局设置，请在 RPCS3 中查看当前游戏的配置。")
            Text("Koala PS 尚未读取 PS3 的实时映射，因此暂不显示可能与实际配置不符的按键图。后续会接入统一的键盘、手柄配置和图示。")
                .foregroundStyle(.secondary)
            HStack {
                Button(model.running ? "回到 RPCS3" : "打开 RPCS3…") {
                    dismiss()
                    if model.running { model.focusGame() } else { model.startPS3(.library) }
                }.buttonStyle(.borderedProminent).disabled(!PS3Engine.supported)
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }.padding(28).frame(width: 680)
    }
}
