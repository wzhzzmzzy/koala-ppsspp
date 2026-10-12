import Foundation
import Darwin

enum GamePlatform: String, Codable, CaseIterable, Identifiable {
    case psp, ps2, ps3
    var id: String { rawValue }
    var title: String { rawValue.uppercased() }
    var extensions: [String] {
        switch self {
        case .psp: return ["iso", "cso", "chd", "pbp", "elf"]
        case .ps2: return ["iso", "chd", "bin", "mdf", "cso", "gz", "elf"]
        case .ps3: return ["iso", "bin", "elf", "self", "sfo", "sfb"]
        }
    }
}

struct Game: Codable, Identifiable, Hashable {
    var id: String
    var path: String
    var title: String
    var bytes: Int64
    var autoState: String?
    var lastPlayed: Date?
    // Old libraries have no platform field and remain PSP libraries.
    var platform: GamePlatform = .psp
    enum CodingKeys: String, CodingKey { case id, path, title, bytes, autoState, lastPlayed, platform }
    init(id: String, path: String, title: String, bytes: Int64, autoState: String? = nil,
         lastPlayed: Date? = nil, platform: GamePlatform = .psp) {
        self.id = id; self.path = path; self.title = title; self.bytes = bytes
        self.autoState = autoState; self.lastPlayed = lastPlayed; self.platform = platform
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id); path = try c.decode(String.self, forKey: .path)
        title = try c.decode(String.self, forKey: .title); bytes = try c.decode(Int64.self, forKey: .bytes)
        autoState = try c.decodeIfPresent(String.self, forKey: .autoState)
        lastPlayed = try c.decodeIfPresent(Date.self, forKey: .lastPlayed)
        platform = try c.decodeIfPresent(GamePlatform.self, forKey: .platform) ?? .psp
    }
}

struct LibraryState: Codable, Equatable {
    var selectedGameID: String?
    var lastPlayedGameID: String?
    var lastPlayedAt: Date?
    var platform: GamePlatform?
}

struct AppPaths {
    let data: URL
    let config: URL
    let state: URL
    let cache: URL
    let runtime: URL
    let legacy: URL
    let isolated: Bool

    init(environment: [String: String] = ProcessInfo.processInfo.environment,
         home: URL = FileManager.default.homeDirectoryForCurrentUser,
         temporary: URL = FileManager.default.temporaryDirectory) {
        func absolute(_ name: String) -> URL? {
            guard let value = environment[name], value.hasPrefix("/") else { return nil }
            return URL(fileURLWithPath: value, isDirectory: true).standardizedFileURL
        }
        legacy = home.appendingPathComponent("Library/Application Support/KoalaPSPNative", isDirectory: true)
        if let override = absolute("KOALA_DATA_DIR") {
            isolated = true
            data = override
            config = override.appendingPathComponent("config", isDirectory: true)
            state = override.appendingPathComponent("state", isDirectory: true)
            cache = override.appendingPathComponent("cache", isDirectory: true)
            runtime = override.appendingPathComponent("run", isDirectory: true)
        } else {
            isolated = false
            data = (absolute("XDG_DATA_HOME") ?? home.appendingPathComponent(".local/share")).appendingPathComponent("koala-psp", isDirectory: true)
            config = (absolute("XDG_CONFIG_HOME") ?? home.appendingPathComponent(".config")).appendingPathComponent("koala-psp", isDirectory: true)
            state = (absolute("XDG_STATE_HOME") ?? home.appendingPathComponent(".local/state")).appendingPathComponent("koala-psp", isDirectory: true)
            cache = (absolute("XDG_CACHE_HOME") ?? home.appendingPathComponent(".cache")).appendingPathComponent("koala-psp", isDirectory: true)
            if let candidate = absolute("XDG_RUNTIME_DIR"),
               let attributes = try? FileManager.default.attributesOfItem(atPath: candidate.path),
               attributes[.type] as? FileAttributeType == .typeDirectory,
               (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
               ((attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0) & 0o777 == 0o700 {
                runtime = candidate.appendingPathComponent("koala-psp", isDirectory: true)
            } else {
                // macOS usually has no XDG_RUNTIME_DIR. Its per-user temp root
                // is used only for per-process IPC, removed on clean shutdown.
                runtime = temporary.appendingPathComponent("koala-psp-\(getuid())", isDirectory: true)
                fputs("Koala PSP: XDG_RUNTIME_DIR unavailable/invalid; using private temporary IPC directory.\n", stderr)
            }
        }
    }

    var engineConfig: URL { config.appendingPathComponent("ppsspp", isDirectory: true) }
    var memstick: URL { data.appendingPathComponent("memstick", isDirectory: true) }

    func prepare() throws {
        for directory in [data, config, state, cache, runtime, engineConfig, memstick] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                     attributes: [.posixPermissions: 0o700])
        }
        let a = try FileManager.default.attributesOfItem(atPath: runtime.path)
        guard a[.type] as? FileAttributeType == .typeDirectory,
              (a[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
              ((a[.posixPermissions] as? NSNumber)?.intValue ?? 0) & 0o777 == 0o700 else {
            throw CocoaError(.fileWriteNoPermission)
        }
    }
}

struct LocalStore {
    let paths: AppPaths
    var libraryURL: URL { paths.data.appendingPathComponent("library.json") }
    var preferencesURL: URL { paths.config.appendingPathComponent("preferences.json") }
    var stateURL: URL { paths.state.appendingPathComponent("library-state.json") }

    func read<T: Decodable>(_ type: T.Type, from url: URL, fallback: T) throws -> T {
        guard FileManager.default.fileExists(atPath: url.path) else { return fallback }
        return try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }
    func write<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    func migrateLegacy() throws {
        let marker = paths.state.appendingPathComponent("migration-v1.json")
        guard !FileManager.default.fileExists(atPath: marker.path) else { return }
        let source = paths.isolated ? paths.data : paths.legacy
        let fm = FileManager.default
        func copyMissing(_ from: URL, _ to: URL, excluding: Set<String> = []) throws {
            guard fm.fileExists(atPath: from.path), from.standardizedFileURL != to.standardizedFileURL else { return }
            let values = try from.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { return }
            if values.isDirectory == true {
                try fm.createDirectory(at: to, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                for child in try fm.contentsOfDirectory(at: from, includingPropertiesForKeys: nil) where !excluding.contains(child.lastPathComponent) {
                    try copyMissing(child, to.appendingPathComponent(child.lastPathComponent), excluding: excluding)
                }
            } else if !fm.fileExists(atPath: to.path) {
                try fm.copyItem(at: from, to: to)
            }
        }
        if !paths.isolated {
            try copyMissing(source.appendingPathComponent("memstick"), paths.memstick, excluding: ["SYSTEM"])
            if !fm.fileExists(atPath: libraryURL.path), fm.fileExists(atPath: source.appendingPathComponent("library.json").path) {
                var games = try read([Game].self, from: source.appendingPathComponent("library.json"), fallback: [])
                let prefix = source.appendingPathComponent("memstick").path + "/"
                for i in games.indices {
                    if let old = games[i].autoState, old.hasPrefix(prefix) {
                        games[i].autoState = paths.memstick.appendingPathComponent(String(old.dropFirst(prefix.count))).path
                    }
                }
                try write(games, to: libraryURL)
            }
        }
        try copyMissing(source.appendingPathComponent("memstick/PSP/SYSTEM"), paths.engineConfig, excluding: ["CACHE", "DUMP"])
        try write(["source": source.path, "policy": "copy missing files; originals retained"], to: marker)
    }
}
