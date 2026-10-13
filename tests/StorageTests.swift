import Foundation
import Darwin

func check(_ expression: @autoclosure () throws -> Bool) rethrows {
    let result = try expression(); assert(result)
}

@main struct StorageTests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("koala-storage-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home")
        let temp = root.appendingPathComponent("temporary")
        let defaults = AppPaths(environment: [:], home: home, temporary: temp)
        assert(defaults.data.path == home.path + "/.local/share/koala-psp")
        assert(defaults.config.path == home.path + "/.config/koala-psp")
        assert(defaults.state.path == home.path + "/.local/state/koala-psp")
        assert(defaults.cache.path == home.path + "/.cache/koala-psp")
        let invalid = AppPaths(environment: ["XDG_DATA_HOME":"relative", "XDG_CONFIG_HOME":"", "XDG_CACHE_HOME":"~/cache"], home: home, temporary: temp)
        assert(invalid.data == defaults.data && invalid.config == defaults.config && invalid.cache == defaults.cache)
        var env: [String:String] = [:]
        for (name, folder) in [("XDG_DATA_HOME","data"),("XDG_CONFIG_HOME","config"),("XDG_STATE_HOME","state"),("XDG_CACHE_HOME","cache")] {
            env[name] = root.appendingPathComponent(folder).path
        }
        let paths = AppPaths(environment: env, home: home, temporary: temp)
        try paths.prepare()
        assert(paths.data.path == root.path + "/data/koala-psp")
        let store = LocalStore(paths: paths)
        let legacySave = paths.legacy.appendingPathComponent("memstick/PSP/PPSSPP_STATE/test.ppst")
        let legacyConfig = paths.legacy.appendingPathComponent("memstick/PSP/SYSTEM/controls.ini")
        for p in [legacySave, legacyConfig] { try FileManager.default.createDirectory(at: p.deletingLastPathComponent(), withIntermediateDirectories: true) }
        try Data("saved-game-fixture".utf8).write(to: legacySave)
        try Data("legacy-keys".utf8).write(to: legacyConfig)
        let existingConfig = paths.engineConfig.appendingPathComponent("controls.ini")
        try Data("keep-current-keys".utf8).write(to: existingConfig)
        let game = Game(id:"game-a", path:"/local/only.iso", title:"Fixture", bytes:123, autoState:legacySave.path)
        try store.write([game], to: paths.legacy.appendingPathComponent("library.json"))
        try store.migrateLegacy()
        var games = try store.read([Game].self, from: store.libraryURL, fallback: [])
        assert(games.count == 1 && games[0].autoState == paths.memstick.appendingPathComponent("PSP/PPSSPP_STATE/test.ppst").path)
        try check(try Data(contentsOf: URL(fileURLWithPath: games[0].autoState!)) == Data(contentsOf: legacySave))
        try check(try String(contentsOf: existingConfig, encoding: .utf8) == "keep-current-keys")
        assert(FileManager.default.fileExists(atPath: legacySave.path))
        games[0].title = "Newer title"; try store.write(games, to: store.libraryURL)
        try store.migrateLegacy()
        try check(try store.read([Game].self, from: store.libraryURL, fallback: [])[0].title == "Newer title")
        let old = try JSONDecoder().decode(PlayerPreferences.self, from: Data(#"{"scale":3,"muted":true}"#.utf8))
        assert(old.vulkanDriver == .moltenvk)
        assert(old.scale == 3 && old.muted && old.audioBuffer == 256 && old.volume == 100 && old.hud == 1)
        let bounded = try JSONDecoder().decode(PlayerPreferences.self, from: Data(#"{"scale":99,"volume":-20,"audioBuffer":0,"textureFilter":99,"anisotropy":-1,"hud":9,"frameSkip":99}"#.utf8))
        assert(bounded.scale == 4 && bounded.volume == 0 && bounded.audioBuffer == 256 && bounded.textureFilter == 4 && bounded.anisotropy == 0 && bounded.hud == 2 && bounded.frameSkip == 2)
        do { _ = try JSONDecoder().decode(PlayerPreferences.self, from: Data(#"{"volume":"bad"}"#.utf8)); assertionFailure("Corrupt settings must not silently reset") } catch { }
        assert(PlayerPreferences.resolution(4) == "1920 × 1088")
        assert(old.launchConfig.contains("iShowStatusFlags = 6"))
        assert(old.launchConfig.contains("GameVolume = 100"))
        var customized = old
        let retired = try JSONDecoder().decode(PlayerPreferences.self, from: Data(#"{"vulkanDriver":"kosmickrisp","scale":3,"volume":42}"#.utf8))
        assert(retired.vulkanDriver == .moltenvk && retired.scale == 3 && retired.volume == 42)
        try Data(#"{"vulkanDriver":"kosmickrisp","scale":3,"volume":42,"futureOption":true}"#.utf8).write(to: store.preferencesURL)
        try store.migrateLegacyDriverPreference()
        let migrated = try JSONSerialization.jsonObject(with: Data(contentsOf: store.preferencesURL)) as! [String: Any]
        assert(migrated["vulkanDriver"] == nil && migrated["volume"] as? Int == 42 && migrated["futureOption"] as? Bool == true)
        try store.migrateLegacyDriverPreference()
        customized.volume = 42; customized.hud = 2; customized.audioBuffer = 512
        customized.vsync = false; customized.textureFilter = 3; customized.anisotropy = 2; customized.smart2D = true
        customized.frameSkip = 1; customized.fillAudioGaps = false
        try check(try JSONDecoder().decode(PlayerPreferences.self, from: JSONEncoder().encode(customized)) == customized)
        assert(customized.launchConfig.contains("AudioBufferSize = 512") && customized.launchConfig.contains("iShowStatusFlags = 22"))
        assert(customized.liveCommand == "settings 1 42 2")
        let settings = PlayerPreferences(scale: 3, muted: true)
        let state = LibraryState(selectedGameID: "game-a", lastPlayedGameID:"game-a", lastPlayedAt:Date(timeIntervalSince1970:123))
        try store.write(settings, to: store.preferencesURL); try store.write(state, to: store.stateURL)
        let reopened = LocalStore(paths: paths)
        try check(try reopened.read(PlayerPreferences.self, from: reopened.preferencesURL, fallback: .init()) == settings)
        try check(try reopened.read(LibraryState.self, from: reopened.stateURL, fallback: .init()) == state)
        try Data("broken json".utf8).write(to: store.libraryURL)
        do { _ = try store.read([Game].self, from: store.libraryURL, fallback: []); assertionFailure("Must surface corrupt data") } catch { }
        try check(try String(contentsOf: store.libraryURL, encoding: .utf8) == "broken json")
        let runtime = root.appendingPathComponent("valid-runtime")
        try FileManager.default.createDirectory(at: runtime, withIntermediateDirectories: true, attributes: [.posixPermissions:0o700])
        env["XDG_RUNTIME_DIR"] = runtime.path
        assert(AppPaths(environment:env,home:home,temporary:temp).runtime.path == runtime.path + "/koala-psp")
        try FileManager.default.setAttributes([.posixPermissions:0o755], ofItemAtPath:runtime.path)
        assert(AppPaths(environment:env,home:home,temporary:temp).runtime != runtime.appendingPathComponent("koala-psp"))
        print("PASS: defaults, absolute XDG overrides, relative/empty rejection, migration and original retention, collision protection, idempotency, preference/state reopen, corrupt-file preservation, runtime permissions")
    }
}
