import Foundation

func check(_ expression: @autoclosure () throws -> Bool) rethrows { let ok = try expression(); assert(ok) }

func expectFailure(_ body: () throws -> Void) {
    do { try body(); fatalError("Expected operation to reject invalid input") } catch { }
}

@main struct PS2Tests {
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("koala-ps2-tests-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let paths = AppPaths(environment: ["KOALA_DATA_DIR": root.path])
        try paths.prepare()
        let engine = PS2Engine(paths: paths)
        let defaults = URL(fileURLWithPath: CommandLine.arguments[1])
        let psp = paths.engineConfig.appendingPathComponent("controls.ini")
        try "PSP settings must remain intact".write(to: psp, atomically: true, encoding: .utf8)
        let old = try JSONDecoder().decode(Game.self, from: Data(#"{"id":"old","path":"/game.iso","title":"Old PSP","bytes":99}"#.utf8))
        assert(old.platform == .psp)
        let ps2Game = Game(id:"new", path:"/same.iso", title:"PS2", bytes:9, platform:.ps2)
        try check(try JSONDecoder().decode(Game.self, from: JSONEncoder().encode(ps2Game)).platform == .ps2)
        try engine.prepare(defaults: defaults)
        assert(engine.data.appendingPathComponent("inis").resolvingSymlinksInPath().path == engine.config.resolvingSymlinksInPath().path)
        try check(try engine.read().value("Folders", "Cache") == engine.cache.path)
        try check(try engine.selectedBIOS() == nil)
        expectFailure { _ = try engine.arguments(for: .bios, log: engine.logs.appendingPathComponent("boot.log")) }
        expectFailure { _ = try engine.arguments(for: .game(URL(fileURLWithPath:"/missing.iso")), log: engine.logs) }
        let settingArgs = try engine.arguments(for: .settings, log: engine.logs.appendingPathComponent("engine.log"))
        assert(settingArgs.contains("-nofullscreen") && !settingArgs.contains("-fullscreen"))
        assert(settingArgs[1] == engine.launchRoot.path)
        var ini = try engine.read()
        ini.lines += ["", "[CustomSettings]", "; preserve this", "Option = user=value", "", "[Pad1]", "Cross = Keyboard/K", "Cross = SDL-0/FaceSouth & Keyboard/Shift"]
        try ini.set("EmuCore/GS", "Renderer", "13")
        try engine.write(ini)
        var options = PS2Options(ini); options.scale = 3; options.volume = 42; options.hud = true
        try engine.apply(options); try engine.prepare(defaults: defaults)
        let saved = try engine.read()
        assert(saved.value("SPU2/Output", "StandardVolume") == "42")
        assert(saved.value("EmuCore/GS", "Renderer") == "13")
        assert(saved.value("CustomSettings", "Option") == "user=value")
        assert(saved.text.contains("; preserve this"))
        assert(saved.entries("Pad1").filter { $0.0 == "Cross" }.count == 3)
        try check(try String(contentsOf: psp, encoding:.utf8) == "PSP settings must remain intact")
        assert(PS2Options(EngineINI("[EmuCore/GS]\nupscale_multiplier = nan")).scale == 1)
        assert(PS2Options(EngineINI("[EmuCore/GS]\nupscale_multiplier = 1e30")).scale == 4)
        let mapping = PS2Mappings.snapshot(saved)
        assert(mapping.matches(codes: [189], device: 10).first?.binding.count == 2)
        assert(mapping.matches(codes: [8], device: 1).first?.action.name == "L2")
        assert(mapping.matches(codes: [67], device: 1).first?.action.name == "Select")
        let weird = PS2Mappings.snapshot(EngineINI("[Pad1]\nType = DualShock2\nCross = SDL-1/FaceSouth & Keyboard/Super\n"))
        assert(weird.matches(codes:[189],device:11).first?.binding.count == 2)
        let cleared = PS2Mappings.snapshot(EngineINI("[Pad1]\nType = None\nCross = SDL-0/FaceSouth\n"))
        assert(cleared.actions.isEmpty)
        // Generated ROMDIR metadata only. This fixture contains no PS2 code and cannot boot.
        var fixture = Data(repeating: 0, count: 4 * 1024 * 1024)
        func entry(_ index: Int, _ name: String, _ length: UInt32) {
            let location = 0x100 + index * 16
            fixture.replaceSubrange(location..<location+name.utf8.count, with: name.utf8)
            for b in 0..<4 { fixture[location+12+b] = UInt8((length >> (8*b)) & 255) }
        }
        entry(0, "RESET", 0x100); entry(1, "ROMDIR", 64); entry(2, "ROMVER", 16)
        fixture.replaceSubrange(0x140..<0x14e, with: "0200AC20040614".utf8)
        let source = root.appendingPathComponent("own bios.bin")
        try fixture.write(to: source)
        let bios = try engine.importBIOS(source)
        assert(bios.region == "北美" && bios.version == "02.00")
        try check(try engine.importBIOS(source) == bios)
        try check(try fm.contentsOfDirectory(atPath: engine.biosDirectory.path).count == 1)
        try check(try Data(contentsOf: source) == fixture)
        let originalSelection = try engine.read().value("Filenames", "BIOS")
        let bad = root.appendingPathComponent("wrong.bin")
        try Data(repeating: 0, count: fixture.count).write(to: bad)
        expectFailure { _ = try engine.importBIOS(bad) }
        try check(try engine.read().value("Filenames", "BIOS") == originalSelection)
        let file = root.appendingPathComponent("-game with spaces.iso")
        try Data("not a game; arguments-only test".utf8).write(to: file)
        let args = try engine.arguments(for: .game(file), log: engine.logs)
        assert(Array(args.suffix(2)) == ["--", file.path])
        assert(args.contains("-fastboot") && args.contains("-batch"))
        try fm.removeItem(at: engine.biosDirectory.appendingPathComponent(bios.filename))
        expectFailure { _ = try engine.arguments(for: .game(file), log: engine.logs) }
        try "[UI]\nSettingsVersion = 999\n".write(to: engine.iniURL, atomically: true, encoding: .utf8)
        expectFailure { try engine.prepare(defaults: defaults) }
        try check(try engine.read().value("UI", "SettingsVersion") == "999")
        try fm.removeItem(at: engine.data.appendingPathComponent("inis"))
        try fm.createDirectory(at: engine.data.appendingPathComponent("inis"), withIntermediateDirectories: false)
        expectFailure { try engine.prepare(defaults: defaults) }
        print("PASS: old library migration, platform roundtrip, XDG paths, config collision protection, BIOS structure/rejection/copy/dedup, missing BIOS preflight, arguments, option merge, input chords and repeated bindings, PSP preservation")
    }
}
