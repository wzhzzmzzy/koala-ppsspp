import Foundation

func check(_ condition: @autoclosure () throws -> Bool) rethrows { let value = try condition(); assert(value) }
func rejects(_ body: () throws -> Void) { do { try body(); fatalError("Expected rejection") } catch {} }

@main struct PS3Tests {
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("koala-ps3-tests-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let engine = PS3Engine(home: root)
        // A tiny generated executable header and metadata, containing no game.
        func write(_ data: Data, _ url: URL) throws {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }
        func sfo(_ title: String, _ category: String) -> Data {
            let keys = Array("TITLE\0CATEGORY\0".utf8)
            let strings = [Array((title + "\0").utf8), Array((category + "\0").utf8)]
            var bytes = [UInt8](repeating: 0, count: 52 + keys.count + strings.flatMap { $0 }.count)
            func put(_ value: Int, _ index: Int, _ count: Int = 4) { for i in 0..<count { bytes[index+i] = UInt8((value >> (8*i)) & 255) } }
            bytes[1] = 0x50; bytes[2] = 0x53; bytes[3] = 0x46
            put(0x101, 4); put(52, 8); put(52 + keys.count, 12); put(2, 16)
            for i in 0..<2 {
                let row = 20 + 16*i
                put(i == 0 ? 0 : 6, row, 2); put(0x204, row+2, 2)
                put(strings[i].count, row+4); put(strings[i].count, row+8)
                put(i == 0 ? 0 : strings[0].count, row+12)
            }
            bytes.replaceSubrange(52..<bytes.count, with: keys + strings.flatMap { $0 })
            return Data(bytes)
        }
        let disc = root.appendingPathComponent("-中文 game/PS3_GAME")
        let boot = disc.appendingPathComponent("USRDIR/EBOOT.BIN")
        try write(Data([0x53,0x43,0x45,0,0]), boot)
        try write(sfo("测试游戏 Ω", "DG"), disc.appendingPathComponent("PARAM.SFO"))
        let content = try PS3Content.inspect(disc.deletingLastPathComponent())
        assert(content.title == "测试游戏 Ω" && content.category == "DG" && content.bytes == 0)
        try check(try PS3Content.inspect(boot).url == content.url)
        try check(try PS3Content.inspect(disc.appendingPathComponent("PARAM.SFO")).url == content.url)
        try check(try PS3Content.inspect(disc).url == content.url)
        let invalid = root.appendingPathComponent("invalid.bin")
        try write(Data("not a game".utf8), invalid)
        rejects { _ = try PS3Content.inspect(invalid) }
        rejects { _ = try PS3Content.inspect(root) }
        try write(Data([0,0x50,0x53,0x46]), root.appendingPathComponent("short.sfo"))
        rejects { _ = try PS3Content.metadata(root.appendingPathComponent("short.sfo")) }
        var corrupt = sfo("title", "HG"); corrupt.replaceSubrange(12..<16, with: [255,255,255,255])
        try write(corrupt, root.appendingPathComponent("corrupt.sfo"))
        rejects { _ = try PS3Content.metadata(root.appendingPathComponent("corrupt.sfo")) }
        try check(try engine.firmwareDescription() == nil)
        rejects { _ = try engine.arguments(for: .game(boot)) }
        // Merely probes the launcher's detection, not real installed firmware.
        let flash = try engine.vfsDirectory("dev_flash")
        try write(Data("release:4.93:fixture\n".utf8), flash.appendingPathComponent("vsh/etc/version.txt"))
        try check(try engine.firmwareDescription() == nil)
        try write(Data("fixture".utf8), flash.appendingPathComponent("sys/external/liblv2.sprx"))
        try check(try engine.firmwareDescription() == "已检测到 PS3 固件 4.93")
        try check(try engine.arguments(for: .game(boot)) == [boot.path])
        try check(try engine.arguments(for: .library).isEmpty)
        try check(try engine.arguments(for: .check) == ["--headless", "--version"])
        let pup = root.appendingPathComponent("PS3UPDAT.PUP")
        var header = Data(repeating: 0, count: 128)
        header.replaceSubrange(0..<8, with: [0x53,0x43,0x45,0x55,0x46,0,0,0])
        header[31] = 1; header[39] = 112; header[47] = 16
        try header.write(to: pup)
        try check(try engine.arguments(for: .firmware(pup)) == ["--installfw", pup.path])
        try Data(header.prefix(120)).write(to: pup)
        rejects { _ = try engine.arguments(for: .firmware(pup)) }
        rejects { _ = try engine.arguments(for: .firmware(invalid)) }
        let pkg = root.appendingPathComponent("game.pkg")
        try write(Data([0x7f,0x50,0x4b,0x47] + Array(repeating: UInt8(0), count: 44)), pkg)
        try check(try engine.arguments(for: .package(pkg)) == ["--installpkg", pkg.path])
        rejects { _ = try PS3Content.inspect(pkg) }
        let hdd = try engine.vfsDirectory("dev_hdd0")
        for (id, category) in [("TEST00001", "HG"), ("TEST00002", "GD")] {
            let game = hdd.appendingPathComponent("game/\(id)")
            try write(sfo(id, category), game.appendingPathComponent("PARAM.SFO"))
            try write(Data([0x7f,0x45,0x4c,0x46]), game.appendingPathComponent("USRDIR/EBOOT.BIN"))
        }
        try check(try engine.installedGames().map(\.title) == ["TEST00001"])
        let vfs = engine.config.appendingPathComponent("vfs.yml")
        let settings = "$(EmulatorDir): '\(root.path)/O''Brien'\n/dev_flash/: $(EmulatorDir)fw/\n/dev_hdd0/: \"\(hdd.path)\"\n"
        try settings.write(to: vfs, atomically: true, encoding: .utf8)
        try check(try engine.vfsDirectory("dev_flash").path == root.appendingPathComponent("O'Brien/fw").path)
        try check(try engine.installedGames().count == 1)
        try check(try String(contentsOf: vfs, encoding: .utf8) == settings)
        try "/dev_flash/: *alias\n".write(to: vfs, atomically: true, encoding: .utf8)
        rejects { _ = try engine.firmwareDescription() }
        let env = engine.environment(["HOME":"/Users/example", "KOALA_VULKAN_DRIVER":"kosmickrisp", "VK_DRIVER_FILES":"bad", "DYLD_INSERT_LIBRARIES":"bad", "QT_PLUGIN_PATH":"bad", "LANG":"en_US.UTF-8"])
        assert(env == ["HOME":"/Users/example", "LANG":"en_US.UTF-8"])
        let game = Game(id:"ps3",path:boot.path,title:"fixture",bytes:0,platform:.ps3)
        try check(try JSONDecoder().decode(Game.self, from: JSONEncoder().encode(game)).platform == .ps3)
        print("PASS: PS3 folder/SFO import, malformed data bounds, firmware preflight, PUP/PKG rejection, CLI arguments, installed-game scan, custom VFS, config preservation, driver isolation, platform persistence")
    }
}
