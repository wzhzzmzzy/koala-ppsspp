import Foundation

struct MappedInput: Codable, Equatable, Hashable {
    var device: Int
    var code: Int
}
struct MappedAction: Codable, Equatable {
    var name: String
    var bindings: [[MappedInput]]
    var label: String {
        ["Cross":"× 叉", "Circle":"○ 圆", "Square":"□ 方块", "Triangle":"△ 三角",
         "L":"L 肩键", "R":"R 肩键", "Up":"十字键 ↑", "Down":"十字键 ↓", "Left":"十字键 ←", "Right":"十字键 →",
         "An.Up":"摇杆 ↑", "An.Down":"摇杆 ↓", "An.Left":"摇杆 ←", "An.Right":"摇杆 →",
         "Start":"START", "Select":"SELECT", "Pause":"游戏菜单", "Pause (no menu)":"暂停 / 继续",
         "Fast-forward":"快进", "SpeedToggle":"切换速度", "Analog speed":"模拟调速", "RapidFire":"连发",
         "Analog limiter":"限制摇杆幅度", "Rewind":"倒带", "Toggle Debugger":"调试器"][name] ?? name
    }
}
struct MappingSnapshot: Codable, Equatable {
    var generation: Int
    var actions: [MappedAction]
    var padDevices: [Int] {
        let ids = Set(actions.flatMap(\.bindings).flatMap { $0 }.map(\.device).filter { (10...19).contains($0) })
        return ids.isEmpty ? [10] : ids.sorted()
    }
    func matches(codes: [Int], device: Int) -> [(action: MappedAction, binding: [MappedInput])] {
        actions.flatMap { action in
            action.bindings.filter { binding in binding.contains { ($0.device == device || $0.device == -1) && codes.contains($0.code) } }
                .map { (action, $0) }
        }
    }
    func summary(codes: [Int], device: Int) -> String {
        let matches = matches(codes: codes, device: device)
        guard !matches.isEmpty else { return "未绑定" }
        let names = Set(matches.map { $0.action.name })
        if codes == PadPart.leftStick.codes && names == Set(["An.Up","An.Down","An.Left","An.Right"]) && matches.allSatisfy({ $0.binding.count == 1 }) { return "PSP 摇杆" }
        if codes == PadPart.dpad.codes && names == Set(["Up","Down","Left","Right"]) && matches.allSatisfy({ $0.binding.count == 1 }) { return "PSP 十字键" }
        let labels = Array(Set(matches.map { $0.action.label + ($0.binding.count > 1 ? "（组合）" : "") })).sorted()
        return labels.joined(separator: " / ")
    }
    static func savedINI(_ text: String) throws -> MappingSnapshot {
        var inside = false, found = false
        var actions: [String: MappedAction] = [:]
        for raw in text.replacingOccurrences(of: "\u{feff}", with: "").components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") { inside = line == "[ControlMapping]"; found = found || inside; continue }
            guard inside, !line.isEmpty, !line.hasPrefix("#"), !line.hasPrefix(";"), let equal = line.firstIndex(of: "=") else { continue }
            let name = line[..<equal].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: equal)...].split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0].trimmingCharacters(in: .whitespaces)
            var bindings: [[MappedInput]] = []
            for alternative in value.split(separator: ",") {
                var chord: [MappedInput] = []
                for component in alternative.split(separator: ":") {
                    let part = component.trimmingCharacters(in: .whitespaces)
                    guard let dash = part.dropFirst().firstIndex(of: "-"),
                          let device = Int(part[..<dash]), let code = Int(part[part.index(after: dash)...]), code >= 0 else {
                        throw MappingError.invalid("\(name) 的按键配置无法解析")
                    }
                    chord.append(MappedInput(device: device, code: code))
                }
                if !chord.isEmpty { bindings.append(chord) }
            }
            actions[name] = MappedAction(name: name, bindings: bindings)
        }
        guard found else { throw MappingError.invalid("未找到 ControlMapping 配置") }
        return MappingSnapshot(generation: 0, actions: actions.values.sorted { $0.name < $1.name })
    }
}
enum MappingError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case let .invalid(s) = self { return s }; return nil }
}

// Physical SDL2 input codes from PPSSPP v1.20.4 SDLJoystick.cpp. In this version
// axis events use the SDL raw indices (0…5), not the Android axis enum names.
enum PadPart: String, CaseIterable, Identifiable {
    case lt, lb, leftStick, l3, dpad, back, guide, start, rightStick, r3, rb, rt, y, b, a, x
    var id: String { rawValue }
    var codes: [Int] {
        switch self {
        case .a: return [189]; case .b: return [190]; case .x: return [191]; case .y: return [188]
        case .lb: return [193]; case .rb: return [192]; case .lt: return [4008]; case .rt: return [4010]
        case .back: return [196]; case .start: return [197]; case .guide: return [4]
        case .l3: return [106]; case .r3: return [107]
        case .dpad: return [19,20,21,22]; case .leftStick: return [4003,4002,4001,4000]
        case .rightStick: return [4007,4006,4005,4004]
        }
    }
    func title(playStation: Bool) -> String {
        switch self {
        case .lt: return playStation ? "L2" : "LT"; case .rt: return playStation ? "R2" : "RT"
        case .lb: return playStation ? "L1" : "LB"; case .rb: return playStation ? "R1" : "RB"
        case .back: return playStation ? "Share" : "Back"; case .start: return playStation ? "Options" : "Start"
        case .guide: return "主菜单键"; case .leftStick: return "左摇杆"; case .rightStick: return "右摇杆"
        case .l3: return "L3 · 按下"; case .r3: return "R3 · 按下"; case .dpad: return "十字键"
        case .a: return playStation ? "×" : "A"; case .b: return playStation ? "○" : "B"
        case .x: return playStation ? "□" : "X"; case .y: return playStation ? "△" : "Y"
        }
    }
    static func physicalName(_ input: MappedInput, playStation: Bool = false) -> String {
        if input.device == 1 {
            return keyboardNames[input.code] ?? "键盘 #\(input.code)"
        }
        let direction: [Int:String] = [19:"↑",20:"↓",21:"←",22:"→",4003:"↑",4002:"↓",4001:"←",4000:"→",4007:"↑",4006:"↓",4005:"←",4004:"→"]
        if let part = allCases.first(where: { $0.codes.contains(input.code) }) {
            let prefix = input.device >= 10 && input.device <= 19 ? "手柄\(input.device-9) " : input.device == -1 ? "任意设备 " : "设备\(input.device) "
            return prefix + part.title(playStation: playStation) + (direction[input.code] ?? "")
        }
        return "设备\(input.device) / 按键 #\(input.code)"
    }
    static let keyboardNames: [Int:String] = {
        var names = [19:"↑",20:"↓",21:"←",22:"→",62:"Space",66:"Return",111:"Esc",59:"左 Shift",60:"右 Shift",61:"Tab"]
        for (index, letter) in "ABCDEFGHIJKLMNOPQRSTUVWXYZ".enumerated() { names[29+index] = String(letter) }
        return names
    }()
    static func keyboardCode(_ name: String) -> Int? { keyboardNames.first { $0.value == name }?.key }
}
