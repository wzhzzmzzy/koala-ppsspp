import Foundation

struct PlayerPreferences: Codable, Equatable {
    var vulkanDriver: VulkanDriver = .moltenvk
    var scale = 1
    var muted = false
    var volume = 100
    var audioBuffer = 256
    var fillAudioGaps = true
    var vsync = true
    var textureFilter = 1
    var anisotropy = 4
    var smart2D = false
    var frameSkip = 0
    var hud = 1

    init(scale: Int = 1, muted: Bool = false) { self.scale = scale; self.muted = muted }
    enum CodingKeys: String, CodingKey {
        case vulkanDriver, scale, muted, volume, audioBuffer, fillAudioGaps, vsync, textureFilter, anisotropy, smart2D, frameSkip, hud
    }
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        vulkanDriver = try c.decodeIfPresent(VulkanDriver.self, forKey: .vulkanDriver) ?? .moltenvk
        scale = try c.decodeIfPresent(Int.self, forKey: .scale) ?? scale
        muted = try c.decodeIfPresent(Bool.self, forKey: .muted) ?? muted
        volume = try c.decodeIfPresent(Int.self, forKey: .volume) ?? volume
        audioBuffer = try c.decodeIfPresent(Int.self, forKey: .audioBuffer) ?? audioBuffer
        fillAudioGaps = try c.decodeIfPresent(Bool.self, forKey: .fillAudioGaps) ?? fillAudioGaps
        vsync = try c.decodeIfPresent(Bool.self, forKey: .vsync) ?? vsync
        textureFilter = try c.decodeIfPresent(Int.self, forKey: .textureFilter) ?? textureFilter
        anisotropy = try c.decodeIfPresent(Int.self, forKey: .anisotropy) ?? anisotropy
        smart2D = try c.decodeIfPresent(Bool.self, forKey: .smart2D) ?? smart2D
        frameSkip = try c.decodeIfPresent(Int.self, forKey: .frameSkip) ?? frameSkip
        hud = try c.decodeIfPresent(Int.self, forKey: .hud) ?? hud
        normalize()
    }
    mutating func normalize() {
        scale = min(4, max(1, scale)); volume = min(100, max(0, volume))
        if ![128, 256, 512, 1024].contains(audioBuffer) { audioBuffer = 256 }
        textureFilter = min(4, max(1, textureFilter)); anisotropy = min(4, max(0, anisotropy))
        frameSkip = min(2, max(0, frameSkip)); hud = min(2, max(0, hud))
    }
    static func resolution(_ scale: Int) -> String { "\(480 * scale) × \(272 * scale)" }
    var resolution: String { Self.resolution(scale) }
    var graphicsDescription: String { "\(scale)× · \(resolution)" }
    var audioBufferMilliseconds: Double { Double(audioBuffer) / 44_100 * 1_000 }
    var liveCommand: String { "settings \(muted ? 1 : 0) \(volume) \(hud)" }

    // Explicitly owned settings override stale per-game profiles on every launch.
    var launchConfig: String {
        """
        [General]
        FirstRun = False
        CheckForNewVersion = False
        RemoteDebuggerOnStartup = False
        RemoteISOShareType = 0
        PauseWhenMinimized = False
        [CPU]
        CPUCore = 1
        [Graphics]
        GraphicsBackend = 3
        InternalResolution = \(scale)
        FrameSkip = \(frameSkip)
        AutoFrameSkip = False
        VerticalSync = \(vsync ? "True" : "False")
        TextureFiltering = \(textureFilter)
        AnisotropyLevel = \(anisotropy)
        Smart2DTexFiltering = \(smart2D ? "True" : "False")
        iShowStatusFlags = \(hud == 0 ? 0 : hud == 1 ? 6 : 22)
        FullScreen = False
        [Sound]
        Enable = \(muted ? "False" : "True")
        GameVolume = \(volume)
        AudioBufferSize = \(audioBuffer)
        FillAudioGaps = \(fillAudioGaps ? "True" : "False")
        [Control]
        ShowTouchControls = False
        """
    }
}
