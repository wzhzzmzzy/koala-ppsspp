import Foundation

@main struct VulkanDriverTests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("koala-vulkan-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("A moved app with spaces.app")
        let frameworks = app.appendingPathComponent("Contents/Helpers/PPSSPPSDL.app/Contents/Frameworks")
        let optional = frameworks.appendingPathComponent("KosmicKrisp")
        try FileManager.default.createDirectory(at: optional, withIntermediateDirectories: true)
        for file in [frameworks.appendingPathComponent("libMoltenVK.dylib"), optional.appendingPathComponent("libvulkan.1.dylib"), optional.appendingPathComponent("libkosmickrisp.dylib"), optional.appendingPathComponent("kosmickrisp_icd.json")] {
            try Data("fixture".utf8).write(to: file)
        }
        assert(VulkanDriver.supports(.moltenvk, majorVersion: 14))
        assert(!VulkanDriver.supports(.kosmickrisp, majorVersion: 25))
        assert(VulkanDriver.supports(.kosmickrisp, majorVersion: 26))
        let base = ["VK_DRIVER_FILES":"/wrong/driver.json", "VK_ICD_FILENAMES":"/another/icd.json", "VK_LOADER_DRIVERS_DISABLE":"*", "SDL_VULKAN_LIBRARY":"wrong", "KK_DEBUG":"all", "MESA_SHADER_CACHE_DIR":"wrong", "KOALA_DATA_DIR":"keep-saves", "PATH":"keep-path"]
        let cache = root.appendingPathComponent("cache")
        let old = try VulkanDriver.moltenvk.environment(base: base, app: app, cache: cache)
        assert(old["VK_DRIVER_FILES"] == nil && old["VK_ICD_FILENAMES"] == nil)
        assert(old["KOALA_DATA_DIR"] == "keep-saves" && old["PATH"] == "keep-path")
        assert(old["SDL_VULKAN_LIBRARY"] == frameworks.appendingPathComponent("libMoltenVK.dylib").path)
        if VulkanDriver.kosmickrisp.availableOnSystem {
            let next = try VulkanDriver.kosmickrisp.environment(base: base, app: app, cache: cache)
            assert(next["VK_DRIVER_FILES"] == optional.appendingPathComponent("kosmickrisp_icd.json").path)
            assert(next["VK_ICD_FILENAMES"] == nil && next["VK_LOADER_DRIVERS_DISABLE"] == nil && next["KK_DEBUG"] == nil)
            assert(next["VK_LOADER_LAYERS_DISABLE"] == "~all~")
            assert(next["KOALA_CACHE_DIR"] != old["KOALA_CACHE_DIR"])
            assert(next["KOALA_DATA_DIR"] == old["KOALA_DATA_DIR"])
            try FileManager.default.removeItem(at: optional.appendingPathComponent("libkosmickrisp.dylib"))
            do {
                _ = try VulkanDriver.kosmickrisp.environment(base: base, app: app, cache: cache)
                fatalError("Missing ICD library must fail without falling back")
            } catch let error as DriverError { assert(error.localizedDescription.contains("缺失")) }
            _ = try VulkanDriver.moltenvk.environment(base: base, app: app, cache: cache)
        }
        do {
            _ = try JSONDecoder().decode(PlayerPreferences.self, from: Data(#"{"vulkanDriver":"unknown"}"#.utf8))
            fatalError("Unknown driver must be reported, not silently substituted")
        } catch is DecodingError { }
        print("PASS: OS gate, driver persistence contract, relocated paths with spaces, environment isolation, separate caches, shared saves, missing driver rejection, MoltenVK recovery")
    }
}
