import SwiftUI

struct ControlsView: View {
    @ObservedObject var model = PlayerModel.shared
    @Environment(\.dismiss) private var dismiss
    @State var page = 0
    @State private var playStation = false
    init(page: Int = 0) { _page = State(initialValue: page) }
    private let orange = Color(red: 0.93, green: 0.52, blue: 0.27)
    @State private var selectedPart: PadPart = .a
    @State private var device = 10
    private func keySummary(_ name: String) -> String {
        guard let code = PadPart.keyboardCode(name) else { return "" }
        return model.mappings?.summary(codes: [code], device: 1) ?? "待同步"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PanelHeader(title: "键盘与手柄", subtitle: model.mappingSource)
            Picker("输入设备", selection: $page) { Text("键盘").tag(0); Text("手柄").tag(1) }.pickerStyle(.segmented)
            if page == 0 { keyboard } else { controller }
            Spacer(minLength: 0)
            Divider()
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("在模拟器里修改按键后，这里的对应关系会自动更新。").font(.callout)
                    Text("点击图中按键查看完整绑定；手柄标记只切换图示，不会修改模拟器配置。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("在模拟器中改键…") { model.editMappings() }.disabled(!model.ready || model.pending)
                Button("完成") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }.padding(26).frame(width: 952, height: 806)
        .onAppear { model.refreshMappings() }
    }
    func key(_ name: String, width: CGFloat = 53) -> some View {
        let label = keySummary(name)
        let active = !label.isEmpty && label != "未绑定" && label != "待同步"
        return VStack(spacing: 5) {
            Text(name).font(.system(size: 17, weight: .semibold, design: .rounded))
            Text(active ? label : " ").font(.system(size: 9)).lineLimit(1)
        }.frame(width: width, height: 51)
            .foregroundStyle(active ? Color.primary : Color.secondary.opacity(0.45))
            .background(active ? orange.opacity(0.16) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(active ? orange.opacity(0.5) : Color.primary.opacity(0.09)))
            .help(label)
            .accessibilityLabel("\(name)：\(label)")
    }
    var keyboard: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 7) {
                HStack { key("Esc", width: 74); Spacer(); Text("橙色按键控制 PSP").font(.caption).foregroundStyle(.secondary) }
                HStack(spacing: 6) { ForEach(["Q","W","E","R","T","Y","U","I","O","P"], id: \.self) { key($0) } }
                HStack(spacing: 6) { ForEach(["A","S","D","F","G","H","J","K","L"], id: \.self) { key($0) }; key("Return", width: 74) }.padding(.leading, 16)
                HStack(spacing: 6) { ForEach(["Z","X","C","V","B","N","M"], id: \.self) { key($0) }; Spacer(); key("↑") }.padding(.leading, 35)
                HStack(spacing: 6) { key("Space", width: 280); Spacer(); key("←"); key("↓"); key("→") }.padding(.leading, 116)
            }.padding(18).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
            Text("橙色键帽表示当前配置中已绑定的键，悬停可查看完整动作。组合键会标为“组合”，需同时按下配置中的其它按键。")
                .font(.callout).foregroundStyle(.secondary)

        }
    }
    var controller: some View {
        VStack(spacing: 12) {
            HStack {
                Picker("配置设备", selection: $device) {
                    ForEach(model.mappings?.padDevices ?? [10], id: \.self) { id in Text("手柄 \(id-9)").tag(id) }
                }.frame(width: 180)
                Text("按模拟器中的设备编号选择").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Picker("图示标记", selection: $playStation) { Text("Xbox / 标准").tag(false); Text("PlayStation").tag(true) }.frame(width: 215)
            }
            ControllerDiagram(snapshot: model.mappings, device: device, playStation: playStation, selection: $selectedPart)
            mappingDetails
            HStack {
                Button("为手柄 1 补齐 L/R 映射") { model.command("bind-shoulders") }.disabled(!model.ready || model.pending)
                Text(model.pending ? "正在更新…" : "保留已有映射；未绑定的肩键会在添加后自动更新标注。").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
        }
        .onChange(of: model.mappings?.padDevices) { _, ids in if let ids, !ids.contains(device) { device = ids.first ?? 10 } }
    }
    var mappingDetails: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(selectedPart.title(playStation: playStation)).font(.system(size: 19,weight: .semibold,design: .rounded))
                Text("完整绑定").font(.caption).foregroundStyle(.secondary)
            }.frame(width: 130, alignment: .leading)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if let snapshot = model.mappings {
                        let matches = snapshot.matches(codes: selectedPart.codes, device: device)
                        if matches.isEmpty { Text("当前配置没有为这个按键分配动作。") }
                        ForEach(Array(matches.enumerated()), id: \.offset) { _, match in
                            Text(match.binding.map { PadPart.physicalName($0, playStation: playStation) }.joined(separator: " + ") + "  →  " + match.action.label)
                                .font(.callout).fixedSize(horizontal: false, vertical: true)
                        }
                    } else { Text("等待读取配置，启动游戏后可显示当前生效的映射。").foregroundStyle(.secondary) }
                    if selectedPart == .rightStick { Text("PSP 没有原生右摇杆，但可在模拟器中绑定其它动作。").font(.caption).foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }.padding(14).frame(height: 86).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}
