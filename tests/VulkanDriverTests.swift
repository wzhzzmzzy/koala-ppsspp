import Foundation

@main struct VulkanDriverTests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("koala-vulkan-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("A moved app with spaces.app")
        let frameworks = app.appendingPathComponent("Contents/Helpers/PPSSPPSDL.app/Contents/Frameworks")
        try FileManager.default.createDirectory(at: frameworks, withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: frameworks.appendingPathComponent("libMoltenVK.dylib"))
        let base = ["VK_DRIVER_FILES":"/wrong/driver.json", "VK_ICD_FILENAMES":"/another/icd.json", "VK_LOADER_DRIVERS_DISABLE":"*", "SDL_VULKAN_LIBRARY":"wrong", "KK_DEBUG":"all", "MESA_SHADER_CACHE_DIR":"wrong", "KOALA_DATA_DIR":"keep-saves", "PATH":"keep-path"]
        let cache = root.appendingPathComponent("cache")
        let old = try VulkanDriver.moltenvk.environment(base: base, app: app, cache: cache)
        assert(old["VK_DRIVER_FILES"] == nil && old["VK_ICD_FILENAMES"] == nil)
        assert(old["KOALA_DATA_DIR"] == "keep-saves" && old["PATH"] == "keep-path")
        assert(old["SDL_VULKAN_LIBRARY"] == frameworks.appendingPathComponent("libMoltenVK.dylib").path)
        let retired = try JSONDecoder().decode(PlayerPreferences.self, from: Data(#"{"vulkanDriver":"kosmickrisp","scale":3,"volume":37}"#.utf8))
        assert(retired.vulkanDriver == .moltenvk && retired.scale == 3 && retired.volume == 37)
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(retired)) as! [String: Any]
        assert(encoded["vulkanDriver"] == nil)
        try FileManager.default.removeItem(at: frameworks.appendingPathComponent("libMoltenVK.dylib"))
        do {
            _ = try VulkanDriver.moltenvk.environment(base: base, app: app, cache: cache)
            fatalError("Missing bundled MoltenVK must be rejected")
        } catch let error as DriverError { assert(error.localizedDescription.contains("缺失")) }
        print("PASS: retired preference migration, setting preservation, relocated paths with spaces, environment isolation, fixed MoltenVK, missing runtime rejection")
    }
}
