import Foundation

// PSP uses the bundled MoltenVK runtime; there is no persisted driver choice.
enum VulkanDriver: String {
    case moltenvk
    var name: String { "MoltenVK" }
    func environment(base: [String: String], app: URL, cache: URL) throws -> [String: String] {
        let frameworks = app.appendingPathComponent("Contents/Helpers/PPSSPPSDL.app/Contents/Frameworks")
        let library = frameworks.appendingPathComponent("libMoltenVK.dylib")
        guard FileManager.default.isReadableFile(atPath: library.path) else {
            throw DriverError.unavailable("\(name) 运行库缺失，请重新解压完整 App。")
        }
        // Inherited SDK, experimental-driver and layer overrides must not change the bundled runtime.
        var env = base.filter { !$0.key.hasPrefix("VK_") && $0.key != "SDL_VULKAN_LIBRARY" && !$0.key.hasPrefix("MESA_") && !$0.key.hasPrefix("KK_") }
        env["KOALA_VULKAN_DRIVER"] = rawValue
        env["SDL_VULKAN_LIBRARY"] = library.path
        let driverCache = cache.appendingPathComponent("vulkan/\(rawValue)")
        try FileManager.default.createDirectory(at: driverCache, withIntermediateDirectories: true)
        env["KOALA_CACHE_DIR"] = driverCache.path
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
