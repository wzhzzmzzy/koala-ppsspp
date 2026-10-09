import Foundation
@main struct MappingTests {
    static func main() throws {
        let ini = "\u{feff}[Other]\nX=bad\n[ControlMapping]\nCross = 10-189\nCircle = 10-190\nSquare = 10-193:10-189,1-40\nTriangle = 11-189\nR = -1-192\nL = \n"
        let s = try MappingSnapshot.savedINI(ini)
        assert(s.padDevices == [10,11])
        assert(s.summary(codes: [189], device:10).contains("× 叉"))
        assert(s.summary(codes: [189], device:10).contains("□ 方块（组合）"))
        assert(!s.summary(codes: [189], device:10).contains("△"))
        assert(s.summary(codes: [189], device:11) == "△ 三角")
        assert(s.summary(codes: [192], device:11) == "R 肩键")
        assert(s.summary(codes: [40], device:1) == "□ 方块")
        assert(s.summary(codes: [197], device:10) == "未绑定")
        assert(s.matches(codes: [189], device:10).first { $0.action.name == "Square" }!.binding.count == 2)
        assert(s.actions.first { $0.name == "L" }!.bindings.isEmpty)
        let roundtrip = try JSONDecoder().decode(MappingSnapshot.self, from: JSONEncoder().encode(s))
        assert(roundtrip == s)
        do { _ = try MappingSnapshot.savedINI("[ControlMapping]\nCross = not-a-code"); assertionFailure("Invalid mapping must surface") } catch { }
        do { _ = try MappingSnapshot.savedINI("[NotMapping]"); assertionFailure("Missing mapping must surface") } catch { }
        assert(PadPart.leftStick.codes == [4003,4002,4001,4000] && PadPart.rightStick.codes == [4007,4006,4005,4004])
        print("PASS: current config, chords without false single-button claims, clears, keyboard, wildcard and multiple devices, JSON round trip, corrupt/missing data")
    }
}
