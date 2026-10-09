import Foundation

// Translate engine-specific physical names into the diagram's common physical
// coordinates. These numbers are never sent to ARMSX2 as input events.
enum PS2Mappings {
    static let actions = ["Up", "Down", "Left", "Right", "Cross", "Circle", "Square", "Triangle", "L1", "R1", "L2", "R2", "L3", "R3", "Start", "Select", "LUp", "LDown", "LLeft", "LRight", "RUp", "RDown", "RLeft", "RRight"]
    static func snapshot(_ ini: EngineINI) -> MappingSnapshot {
        let renamed = ["LUp":"An.Up", "LDown":"An.Down", "LLeft":"An.Left", "LRight":"An.Right",
                       "RUp":"右摇杆 ↑", "RDown":"右摇杆 ↓", "RLeft":"右摇杆 ←", "RRight":"右摇杆 →"]
        let rows = ini.entries("Pad1")
        guard ini.value("Pad1", "Type") == "DualShock2" else { return MappingSnapshot(generation: 0, actions: []) }
        return MappingSnapshot(generation: 0, actions: actions.map { name in
            let bindings = rows.filter { $0.0 == name && !$0.1.isEmpty }.map { row in
                row.1.components(separatedBy: " & ").map { physical($0) }
            }
            return MappedAction(name: renamed[name] ?? name, bindings: bindings)
        }, platform: "ps2")
    }
    static func physical(_ name: String) -> MappedInput {
        let components = name.split(separator: "/", maxSplits: 1).map(String.init)
        guard components.count == 2 else { return unknown(name) }
        let key = components[1]
        if components[0] == "Keyboard" {
            let aliases = ["Up":"↑", "Down":"↓", "Left":"←", "Right":"→", "Escape":"Esc", "Shift":"左 Shift"]
            if let code = PadPart.keyboardCode(aliases[key] ?? key) { return MappedInput(device: 1, code: code) }
        }
        if components[0].hasPrefix("SDL-"), let index = Int(components[0].dropFirst(4)), (0...9).contains(index) {
            let keys = ["FaceSouth":189, "FaceEast":190, "FaceWest":191, "FaceNorth":188,
                        "A":189, "B":190, "X":191, "Y":188,
                        "LeftShoulder":193, "RightShoulder":192, "+LeftTrigger":4008, "+RightTrigger":4010,
                        "Back":196, "Start":197, "Guide":4, "LeftStick":106, "RightStick":107,
                        "DPadUp":19, "DPadDown":20, "DPadLeft":21, "DPadRight":22,
                        "-LeftY":4003, "+LeftY":4002, "-LeftX":4001, "+LeftX":4000,
                        "-RightY":4007, "+RightY":4006, "-RightX":4005, "+RightX":4004]
            if let code = keys[key] { return MappedInput(device: 10 + index, code: code) }
        }
        return unknown(name)
    }
    static func unknown(_ name: String) -> MappedInput {
        // Keep unsupported chord members: dropping them would falsely label a
        // combination as a one-button binding. Raw bindings remain in ARMSX2.
        MappedInput(device: 100, code: Int(name.utf8.reduce(UInt32(2166136261)) { ($0 ^ UInt32($1)) &* 16777619 }))
    }
}
