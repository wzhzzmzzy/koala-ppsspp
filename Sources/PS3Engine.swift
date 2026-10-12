import Foundation

enum PS3Error: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case let .invalid(message) = self { return message }; return nil }
}

// The standalone engine owns input profiles. A future input bridge can consume
// the same launch intent without changing the library's persistent game paths.
struct PS3Engine {
    static let version = "0.0.43-20284"
    static let relativeExecutable = "Contents/Helpers/RPCS3.app/Contents/MacOS/rpcs3"
    static let firmwareURL = URL(string: "https://www.playstation.com/en-us/support/hardware/ps3/system-software/")!
    let home: URL
    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) { self.home = home }
    var config: URL { home.appendingPathComponent("Library/Application Support/rpcs3") }
    var cache: URL { home.appendingPathComponent("Library/Caches/rpcs3") }
    var log: URL { cache.appendingPathComponent("RPCS3.log") }
    var inputOwner: String { "RPCS3 原生 Pads 设置" }
    static var supported: Bool { ProcessInfo.processInfo.isOperatingSystemAtLeast(.init(majorVersion: 15, minorVersion: 0, patchVersion: 0)) }

    // Read only the root scalar paths emitted by RPCS3's VFS editor. Never
    // rewrite user YAML or silently ignore a path syntax we cannot understand.
    func vfsDirectory(_ name: String) throws -> URL {
        let file = config.appendingPathComponent("vfs.yml")
        var values: [String: String] = [:]
        if FileManager.default.fileExists(atPath: file.path) {
            for line in try String(contentsOf: file, encoding: .utf8).components(separatedBy: .newlines) {
                guard line.first != " ", let split = line.range(of: ": ") else { continue }
                func scalar(_ raw: String) throws -> String {
                    let text = raw.trimmingCharacters(in: .whitespaces)
                    if text.hasPrefix("\"") {
                        guard let string = try? JSONDecoder().decode(String.self, from: Data(text.utf8)) else {
                            throw PS3Error.invalid("无法读取 RPCS3 的 VFS 路径，请在原生设置中检查。")
                        }
                        return string
                    }
                    if text.hasPrefix("'") && text.hasSuffix("'") { return String(text.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'") }
                    if let first = text.first, "|>&*!{[".contains(first) { throw PS3Error.invalid("RPCS3 VFS 使用了复杂 YAML 路径，请在原生设置中管理。") }
                    return text.components(separatedBy: " #")[0]
                }
                let key = try scalar(String(line[..<split.lowerBound]))
                if key == "$(EmulatorDir)" || key == "/\(name)/" { values[key] = try scalar(String(line[split.upperBound...])) }
            }
        }
        let customRoot = values["$(EmulatorDir)"] ?? ""
        let base = customRoot.isEmpty ? config.path : customRoot
        let value = values["/\(name)/"] ?? ""
        let path = (value.isEmpty ? "$(EmulatorDir)\(name)/" : value)
            .replacingOccurrences(of: "$(EmulatorDir)", with: base.hasSuffix("/") ? base : base + "/")
        guard path.hasPrefix("/"), !path.contains("$(") else { throw PS3Error.invalid("RPCS3 VFS 路径不是可识别的绝对路径，请使用原生设置检查。") }
        return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    }

    func firmwareDescription() throws -> String? {
        let flash = try vfsDirectory("dev_flash")
        let version = flash.appendingPathComponent("vsh/etc/version.txt")
        guard FileManager.default.isReadableFile(atPath: flash.appendingPathComponent("sys/external/liblv2.sprx").path),
              let text = try? String(contentsOf: version, encoding: .utf8),
              let line = text.components(separatedBy: .newlines).first(where: { $0.hasPrefix("release:") }) else { return nil }
        let release = line.dropFirst(8).split(separator: ":").first.map(String.init) ?? ""
        return "已检测到 PS3 固件 \(release)"
    }

    enum Launch { case library, game(URL), firmware(URL), package(URL), check }
    func arguments(for launch: Launch) throws -> [String] {
        switch launch {
        case .library: return []
        case .check: return ["--headless", "--version"]
        case .game(let url):
            guard try firmwareDescription() != nil else { throw PS3Error.invalid("尚未检测到 PS3 固件。请先在 PS3 设置中安装 Sony 的 PS3UPDAT.PUP。") }
            let content = try PS3Content.inspect(url)
            // Keep the native GUI available for Pads, per-game settings and
            // firmware errors. Fullscreen and input profile flags stay unset.
            return [content.url.path]
        case .firmware(let url):
            try PS3Content.validateInstaller(url, firmware: true)
            return ["--installfw", url.standardizedFileURL.path]
        case .package(let url):
            try PS3Content.validateInstaller(url, firmware: false)
            return ["--installpkg", url.standardizedFileURL.path]
        }
    }

    func installedGames() throws -> [PS3Content] {
        let directory = try vfsDirectory("dev_hdd0").appendingPathComponent("game")
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).compactMap { folder in
            guard let content = try? PS3Content.inspect(folder), content.category == "HG" else { return nil }
            return content
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func environment(_ base: [String: String]) -> [String: String] {
        // Do not pass PSP's experimental driver or process instrumentation into
        // the official PS3 engine. Its bundled MoltenVK remains authoritative.
        base.filter { key, _ in
            !key.hasPrefix("KOALA_") && !key.hasPrefix("VK_") && !key.hasPrefix("MVK_") &&
            !key.hasPrefix("MESA_") && !key.hasPrefix("DYLD_") && !key.hasPrefix("QT_") &&
            key != "SDL_VULKAN_LIBRARY" && key != "RPCS3_CONFIG_DIR"
        }
    }
}

struct PS3Content {
    let url: URL
    let title: String
    let bytes: Int64
    let category: String?

    static func inspect(_ input: URL) throws -> PS3Content {
        let fm = FileManager.default
        var url = input.standardizedFileURL.resolvingSymlinksInPath()
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
        if values.isDirectory == true {
            let candidates = ["PS3_GAME/USRDIR/EBOOT.BIN", "USRDIR/EBOOT.BIN", "EBOOT.BIN"]
            guard let file = candidates.map({ url.appendingPathComponent($0) }).first(where: { fm.isReadableFile(atPath: $0.path) }) else {
                throw PS3Error.invalid("这个文件夹没有 PS3_GAME/USRDIR/EBOOT.BIN 或 USRDIR/EBOOT.BIN，请选择解密后的 PS3 游戏。")
            }
            url = file
        } else if url.lastPathComponent.uppercased() == "PS3_DISC.SFB" {
            return try inspect(url.deletingLastPathComponent())
        } else if url.lastPathComponent.uppercased() == "PARAM.SFO" {
            return try inspect(url.deletingLastPathComponent())
        }
        let attr = try fm.attributesOfItem(atPath: url.path)
        guard attr[.type] as? FileAttributeType == .typeRegular, fm.isReadableFile(atPath: url.path) else { throw PS3Error.invalid("请选择可读取的 PS3 游戏文件。") }
        let size = (attr[.size] as? NSNumber)?.int64Value ?? 0
        let ext = url.pathExtension.lowercased()
        guard ["iso", "bin", "elf", "self"].contains(ext), size > 0 else {
            throw PS3Error.invalid("请选择 PS3 游戏文件夹、ISO 或 EBOOT.BIN。PKG 请使用「安装 PKG」。")
        }
        if ext != "iso" {
            let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
            let magic = Array(try file.read(upToCount: 4) ?? Data())
            guard magic == [0x53, 0x43, 0x45, 0] || magic == [0x7f, 0x45, 0x4c, 0x46] else {
                throw PS3Error.invalid("该文件不是可识别的 PS3 SELF / ELF 可执行文件。")
            }
        }
        let gameRoot = url.deletingLastPathComponent().deletingLastPathComponent()
        let sfo = gameRoot.appendingPathComponent("PARAM.SFO")
        let info = (try? metadata(sfo)) ?? [:]
        let fallback = url.lastPathComponent.uppercased() == "EBOOT.BIN"
            ? (gameRoot.lastPathComponent == "PS3_GAME" ? gameRoot.deletingLastPathComponent().lastPathComponent : gameRoot.lastPathComponent)
            : url.deletingPathExtension().lastPathComponent
        return PS3Content(url: url, title: info["TITLE"].flatMap { $0.isEmpty ? nil : $0 } ?? fallback,
                          bytes: ext == "iso" ? size : 0, category: info["CATEGORY"])
    }

    // Bounded PARAM.SFO parsing; game directories can be many GB, so importing
    // never walks their contents or loads a game executable into memory.
    static func metadata(_ url: URL) throws -> [String: String] {
        let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
        let data = Array(try file.read(upToCount: 1_048_577) ?? Data())
        guard data.count >= 20, data.count <= 1_048_576, Array(data.prefix(4)) == [0, 0x50, 0x53, 0x46] else { throw PS3Error.invalid("无效的 PARAM.SFO。") }
        func n(_ offset: Int, _ size: Int = 4) -> Int { (0..<size).reduce(0) { $0 | (Int(data[offset + $1]) << ($1 * 8)) } }
        let keys = n(8), values = n(12), count = n(16)
        guard count <= 4096, 20 + count * 16 <= keys, keys <= values, values <= data.count else { throw PS3Error.invalid("PARAM.SFO 索引越界。") }
        var result: [String: String] = [:]
        for i in 0..<count {
            let row = 20 + i * 16, key = keys + n(row, 2), length = n(row + 4), value = values + n(row + 12)
            guard key < values, key >= keys, length <= data.count, value <= data.count, length <= data.count - value else { throw PS3Error.invalid("PARAM.SFO 数据越界。") }
            guard n(row + 2, 2) == 0x0204, let end = data[key..<values].firstIndex(of: 0) else { continue }
            let name = String(decoding: data[key..<end], as: UTF8.self)
            result[name] = String(decoding: data[value..<(value + length)].prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        return result
    }

    static func validateInstaller(_ url: URL, firmware: Bool) throws {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attrs[.type] as? FileAttributeType == .typeRegular else { throw PS3Error.invalid("请选择安装文件。") }
        let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
        let header = Array(try file.read(upToCount: 48) ?? Data())
        let size = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
        if firmware {
            guard header.count == 48, Array(header.prefix(8)) == [0x53, 0x43, 0x45, 0x55, 0x46, 0, 0, 0] else { throw PS3Error.invalid("不是有效的 PS3UPDAT.PUP 文件。") }
            func big(_ offset: Int) -> UInt64 { (0..<8).reduce(0) { ($0 << 8) | UInt64(header[offset + $1]) } }
            let count = big(24), headerSize = big(32), payload = big(40)
            guard count > 0, headerSize >= 48, headerSize <= size, count <= (headerSize - 48) / 64, payload <= size - headerSize else { throw PS3Error.invalid("PS3 固件已截断或文件头损坏，请重新下载。") }
        } else {
            guard header.count == 48, Array(header.prefix(4)) == [0x7f, 0x50, 0x4b, 0x47] else { throw PS3Error.invalid("不是可识别的 PlayStation PKG 文件。") }
        }
        // Full integrity/platform checks and installation belong to RPCS3.
    }
}
