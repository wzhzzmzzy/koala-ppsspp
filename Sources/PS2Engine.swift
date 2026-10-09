import Foundation
import CryptoKit

// Preserve unknown options, comments and repeated input bindings when changing
// the small set of settings owned by the launcher. ARMSX2 uses SimpleINI.
struct EngineINI {
    var lines: [String]
    init(_ text: String) { lines = text.replacingOccurrences(of: "\u{feff}", with: "").components(separatedBy: .newlines) }
    var text: String { lines.joined(separator: "\n") }
    func entries(_ section: String) -> [(String, String)] {
        var current = "", result: [(String, String)] = []
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") && line.hasSuffix("]") { current = String(line.dropFirst().dropLast()); continue }
            guard current == section, !line.hasPrefix(";"), !line.hasPrefix("#"), let eq = line.firstIndex(of: "=") else { continue }
            result.append((line[..<eq].trimmingCharacters(in: .whitespaces), line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)))
        }
        return result
    }
    func value(_ section: String, _ key: String) -> String? { entries(section).first { $0.0 == key }?.1 }
    mutating func set(_ section: String, _ key: String, _ value: String) throws {
        guard !value.contains("\n"), !value.contains("\r") else { throw PS2Error.invalid("路径或配置不能包含换行。") }
        var current = "", start: Int?, end = lines.count, matches: [Int] = []
        for i in lines.indices {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") && line.hasSuffix("]") {
                if current == section { end = i }
                current = String(line.dropFirst().dropLast())
                if current == section { start = i }
            } else if current == section, let eq = line.firstIndex(of: "="), line[..<eq].trimmingCharacters(in: .whitespaces) == key { matches.append(i) }
        }
        if let first = matches.first {
            lines[first] = "\(key) = \(value)"
            for i in matches.dropFirst().reversed() { lines.remove(at: i) }
        } else if start != nil { lines.insert("\(key) = \(value)", at: end) }
        else { lines += ["", "[\(section)]", "\(key) = \(value)", ""] }
    }
}

enum PS2Error: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case let .invalid(message) = self { return message }; return nil }
}

struct PS2BIOS: Equatable {
    let filename: String
    let version: String
    let region: String
    var description: String { "\(region) · BIOS \(version)" }
    // Check the ROMDIR table and its ROMVER entry, not just a .bin extension.
    // This is a structural check; successful boot must still be verified by ARMSX2.
    static func inspect(_ url: URL) throws -> PS2BIOS {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let count = (attrs[.size] as? NSNumber)?.intValue ?? 0
        guard attrs[.type] as? FileAttributeType == .typeRegular, (512 * 1024...8 * 1024 * 1024).contains(count) else {
            throw PS2Error.invalid("这不是支持的 PS2 BIOS 文件（应为 512 KiB–8 MiB 的原始 ROM，不能是 ZIP 或游戏 ISO）。")
        }
        let bytes = [UInt8](try Data(contentsOf: url))
        func name(_ i: Int) -> String { String(bytes: bytes[i..<i+10].prefix { $0 != 0 }, encoding: .ascii) ?? "" }
        func size(_ i: Int) -> Int { (0..<4).reduce(0) { $0 | (Int(bytes[i+12+$1]) << (8*$1)) } }
        for start in stride(from: 0, to: min(bytes.count - 16, 512 * 1024), by: 16) where name(start) == "RESET" {
            var offset = 0, romver: String?, directory = false, complete = false
            for i in stride(from: start, to: min(bytes.count - 16, start + 65536), by: 16) {
                let entry = name(i), length = size(i)
                if entry.isEmpty { complete = true; break }
                guard offset <= bytes.count, length <= bytes.count - offset else { break }
                if entry == "ROMDIR" { directory = true }
                if entry == "ROMVER", length >= 14 {
                    romver = String(bytes: bytes[offset..<offset+14], encoding: .ascii)
                }
                offset += (length + 15) & ~15
            }
            if directory, complete, let v = romver {
                let c = Array(v)
                guard c.count == 14, c[0..<4].allSatisfy(\.isNumber), c[6..<14].allSatisfy(\.isNumber) else { continue }
                let regions: [Character:String] = ["J":"日本", "A":"北美", "E":"欧洲", "H":"亚洲", "C":"中国", "T":"开发机", "X":"测试机", "P":"Free"]
                guard let region = regions[c[4]], c[5] != "Z" else { continue }
                return PS2BIOS(filename: url.lastPathComponent, version: "\(String(c[0..<2])).\(String(c[2..<4]))", region: region)
            }
        }
        throw PS2Error.invalid("未找到完整的 PS2 ROMDIR / ROMVER 结构。请选择从自己的 PS2 提取的 BIOS 主文件。")
    }
}

struct PS2Options {
    var scale: Int
    var volume: Int
    var hud: Bool
    init(_ ini: EngineINI) {
        let rawScale = Double(ini.value("EmuCore/GS", "upscale_multiplier") ?? "1") ?? 1
        scale = rawScale.isFinite ? Int(min(4, max(1, rawScale))) : 1
        volume = min(100, max(0, Int(ini.value("SPU2/Output", "StandardVolume") ?? "100") ?? 100))
        hud = ini.value("EmuCore/GS", "OsdShowFPS") == "true"
    }
}

struct PS2Engine {
    static let version = "nightly-20261008 · b1f3196b9e"
    static let relativeExecutable = "Contents/Helpers/ARMSX2.app/Contents/MacOS/ARMSX2"
    let paths: AppPaths
    var launchRoot: URL { paths.data.appendingPathComponent("ps2") }
    var data: URL { launchRoot.appendingPathComponent("ARMSX2") }
    var config: URL { paths.config.appendingPathComponent("armsx2") }
    var iniURL: URL { config.appendingPathComponent("PCSX2.ini") }
    var biosDirectory: URL { data.appendingPathComponent("bios") }
    var logs: URL { paths.state.appendingPathComponent("armsx2") }
    var cache: URL { paths.cache.appendingPathComponent("armsx2") }
    func read() throws -> EngineINI { EngineINI(try String(contentsOf: iniURL, encoding: .utf8)) }
    func write(_ ini: EngineINI) throws { try ini.text.write(to: iniURL, atomically: true, encoding: .utf8) }
    func prepare(defaults: URL) throws {
        let fm = FileManager.default
        for dir in [data, config, biosDirectory, logs, cache] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions:0o700])
        }
        // ARMSX2 hardcodes DataRoot/inis. Only this owned link redirects it to XDG config.
        let link = data.appendingPathComponent("inis")
        if (try? link.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true || fm.fileExists(atPath: link.path) {
            guard link.resolvingSymlinksInPath().standardizedFileURL.path == config.resolvingSymlinksInPath().standardizedFileURL.path else {
                throw PS2Error.invalid("PS2 设置目录已存在且指向不同位置，已保留原内容：\(link.path)")
            }
        } else { try fm.createSymbolicLink(at: link, withDestinationURL: config) }
        let fresh = !fm.fileExists(atPath: iniURL.path)
        var ini = fresh ? EngineINI(try String(contentsOf: defaults, encoding: .utf8)) : try read()
        guard ini.value("UI", "SettingsVersion") == "1" else { throw PS2Error.invalid("ARMSX2 设置版本不兼容；现有配置已保留。") }
        let folders = ["Bios":biosDirectory, "Cache":cache, "Logs":logs,
                       "GameSettings":config.appendingPathComponent("gamesettings"), "InputProfiles":config.appendingPathComponent("inputprofiles"),
                       "DebuggerLayouts":config.appendingPathComponent("debuggerlayouts"), "DebuggerSettings":config.appendingPathComponent("debuggersettings")]
        for (key, value) in folders { try ini.set("Folders", key, value.path) }
        try ini.set("UI", "SetupWizardIncomplete", "false")
        try ini.set("UI", "StartFullscreen", "false")
        try ini.set("UI", "StartBigPictureMode", "false")
        try ini.set("UI", "PauseOnFocusLoss", "false")
        try ini.set("UI", "RenderToSeparateWindow", "true")
        try ini.set("AutoUpdater", "CheckAtStartup", "false")
        if fresh {
            try ini.set("EmuCore/GS", "Renderer", "17") // ARMSX2 GSRendererType::Metal.
            try ini.set("EmuCore/GS", "OsdShowFPS", "true")
            try ini.set("EmuCore/GS", "OsdShowSpeed", "true")
            try ini.set("EmuCore/GS", "OsdShowResolution", "true")
            try ini.set("EmuCore", "SaveStateOnShutdown", "true")
        }
        try write(ini)
    }
    func selectedBIOS() throws -> PS2BIOS? {
        guard let name = try read().value("Filenames", "BIOS"), !name.isEmpty else { return nil }
        let url = name.hasPrefix("/") ? URL(fileURLWithPath: name) : biosDirectory.appendingPathComponent(name)
        return try PS2BIOS.inspect(url)
    }
    @discardableResult func importBIOS(_ source: URL) throws -> PS2BIOS {
        _ = try PS2BIOS.inspect(source)
        let content = try Data(contentsOf: source)
        let hash = SHA256.hash(data: content).map { String(format: "%02x", $0) }.joined()
        let target = biosDirectory.appendingPathComponent("bios-\(hash).bin")
        if FileManager.default.fileExists(atPath: target.path) {
            guard try Data(contentsOf: target) == content else { throw PS2Error.invalid("BIOS 目标文件冲突，已保留原内容。") }
        } else { try content.write(to: target, options: .atomic) }
        var ini = try read(); try ini.set("Filenames", "BIOS", target.lastPathComponent); try write(ini)
        return try PS2BIOS.inspect(target)
    }
    func apply(_ options: PS2Options) throws {
        var ini = try read()
        try ini.set("EmuCore/GS", "upscale_multiplier", String(min(4, max(1, options.scale))))
        try ini.set("SPU2/Output", "StandardVolume", String(min(100, max(0, options.volume))))
        for key in ["OsdShowFPS", "OsdShowSpeed", "OsdShowResolution", "OsdShowFrameTimes"] {
            try ini.set("EmuCore/GS", key, options.hud ? "true" : "false")
        }
        try write(ini)
    }
    enum Launch { case game(URL), bios, settings, check }
    func arguments(for launch: Launch, log: URL) throws -> [String] {
        var args = ["-datapath", launchRoot.path, "-logfile", log.path, "-nofullscreen"]
        switch launch {
        case .game(let url):
            guard try selectedBIOS() != nil else { throw PS2Error.invalid("先导入 PS2 BIOS，再启动游戏。BIOS 是主机启动程序，与游戏 ISO 不同。") }
            guard FileManager.default.isReadableFile(atPath: url.path) else { throw PS2Error.invalid("找不到游戏文件，请重新添加。") }
            args += ["-batch", "-fastboot", "--", url.path]
        case .bios:
            guard try selectedBIOS() != nil else { throw PS2Error.invalid("请先导入 PS2 BIOS。") }
            args += ["-batch", "-bios"]
        case .settings: break
        case .check: args += ["-testconfig"]
        }
        return args
    }
}
