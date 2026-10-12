import Foundation

// A launch-time choice: never replace a driver beneath an active GPU session.
enum VulkanDriver: String, Codable, CaseIterable, Identifiable {
    case moltenvk, kosmickrisp
    var id: String { rawValue }
    var title: String { self == .moltenvk ? "MoltenVK · 默认" : "KosmicKrisp · 实验性" }
    var name: String { self == .moltenvk ? "MoltenVK" : "KosmicKrisp" }
    var availableOnSystem: Bool {
        Self.supports(self, majorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
    }
    static func supports(_ driver: Self, majorVersion: Int) -> Bool {
        majorVersion >= (driver == .kosmickrisp ? 26 : 14)
    }
    func environment(base: [String: String], app: URL, cache: URL) throws -> [String: String] {
        guard availableOnSystem else {
            throw DriverError.unavailable("KosmicKrisp 需要 Apple Silicon 和 macOS 26 或更新版本；请在播放设置中选择 MoltenVK。")
        }
        let frameworks = app.appendingPathComponent("Contents/Helpers/PPSSPPSDL.app/Contents/Frameworks")
        let library = frameworks.appendingPathComponent(self == .kosmickrisp ? "KosmicKrisp/libvulkan.1.dylib" : "libMoltenVK.dylib")
        guard FileManager.default.isReadableFile(atPath: library.path) else {
            throw DriverError.unavailable("\(name) 运行库缺失，请重新解压完整的实验版 App，或切换图形驱动。")
        }
        // Restrict discovery to our bundled ICD; inherited SDK/layer overrides must not change the chosen driver.
        var env = base.filter { !$0.key.hasPrefix("VK_") && $0.key != "SDL_VULKAN_LIBRARY" && !$0.key.hasPrefix("MESA_") && !$0.key.hasPrefix("KK_") }
        env["KOALA_VULKAN_DRIVER"] = rawValue
        env["SDL_VULKAN_LIBRARY"] = library.path
        let driverCache = cache.appendingPathComponent("vulkan/\(rawValue)")
        try FileManager.default.createDirectory(at: driverCache, withIntermediateDirectories: true)
        env["KOALA_CACHE_DIR"] = driverCache.path
        if self == .kosmickrisp {
            let icd = frameworks.appendingPathComponent("KosmicKrisp/kosmickrisp_icd.json")
            let driver = frameworks.appendingPathComponent("KosmicKrisp/libkosmickrisp.dylib")
            guard [icd, driver].allSatisfy({ FileManager.default.isReadableFile(atPath: $0.path) }) else {
                throw DriverError.unavailable("KosmicKrisp 驱动文件缺失，请重新解压完整的实验版 App；不会自动回退到其他驱动。")
            }
            env["VK_DRIVER_FILES"] = icd.path
            env["VK_LOADER_LAYERS_DISABLE"] = "~all~"
            env["MESA_SHADER_CACHE_DIR"] = driverCache.appendingPathComponent("mesa").path
        }
        return env
    }
}
enum DriverError: LocalizedError {
    case unavailable(String)
    var errorDescription: String? { if case let .unavailable(message) = self { return message }; return nil }
}

struct VulkanDriverReport: Codable {
    var requested: String
    var driverName: String
    var driverInfo: String
    var deviceName: String
    var apiVersion: String
    var driverID: UInt32
    var deviceCreated: Bool
}
