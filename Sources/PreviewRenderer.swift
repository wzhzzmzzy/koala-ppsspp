import AppKit
import SwiftUI

// Offscreen rendering only: no window is ordered front and no activation occurs.
@MainActor func renderPreviews(to directory: URL) throws {
    NSApplication.shared.setActivationPolicy(.prohibited)
    // NSColor-backed backgrounds must resolve in the same appearance as SwiftUI.
    NSApplication.shared.appearance = NSAppearance(named: .aqua)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let model = PlayerModel.shared
    model.preferences = PlayerPreferences(scale: 3)
    model.preferences.hud = 2
    model.refreshMappings()
    var panels: [(String, AnyView)] = [
        ("settings-video", AnyView(PlayerSettingsView(model: model))),
        ("settings-audio", AnyView(PlayerSettingsView(model: model, tab: 1))),
        ("settings-hud", AnyView(PlayerSettingsView(model: model, tab: 2))),
        ("controls-keyboard", AnyView(ControlsView())),
        ("keyboard-layout", AnyView(ControlsView().keyboard.frame(width: 900).padding(18))),
        ("controls-gamepad", AnyView(ControlsView(page: 1))),
        ("controller-artwork", AnyView(ControllerArtwork().frame(width: 596, height: 335).background(.white))),
        ("controller-artwork-wide", AnyView(ControllerArtwork().frame(width: 800, height: 335).background(.white))),
        ("diagnostics", AnyView(DiagnosticsView(model: model)))
    ]
    // Optional visual QA input only; the reference is never bundled in the app.
    if let path = ProcessInfo.processInfo.environment["KOALA_CONTROLLER_REFERENCE"], let reference = NSImage(contentsOfFile: path) {
        let comparison = HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 12) {
                Text("用户参考图 · 596 × 335").font(.system(size: 14, weight: .medium))
                Image(nsImage: reference).resizable().aspectRatio(contentMode: .fit).frame(width: 596, height: 335)
            }
            VStack(spacing: 12) {
                Text("新版原生绘制 · 相同画布与比例").font(.system(size: 14, weight: .medium))
                ControllerArtwork().frame(width: 596, height: 335)
            }
        }.padding(.vertical, 18).background(.white)
        panels.append(("controller-reference-comparison", AnyView(comparison)))
    }
    let previewPS2 = CommandLine.arguments.contains("--ps2")
    if previewPS2 {
        model.platform = .ps2; model.refreshPS2(); model.refreshMappings()
        panels = [
            ("platform-selector", AnyView(PlayerView(model: model).platformSelector.frame(width: 240))),
            ("ps2-library", AnyView(PlayerView(model: model).frame(width: 1180, height: 860))),
            ("ps2-settings", AnyView(PS2SettingsView(model: model))),
            ("ps2-keyboard", AnyView(ControlsView())),
            ("ps2-controller", AnyView(ControlsView(page: 1)))
        ]
    }
    if CommandLine.arguments.contains("--library") {
        panels = [
            ("library-header", AnyView(PlayerView(model: model).libraryHeader.frame(width: 680).padding(30))),
            ("library", AnyView(PlayerView(model: model).frame(width: 1180, height: 860)))
        ]
    }
    if CommandLine.arguments.contains("--ps3") {
        model.platform = .ps3; model.refreshPS3(); model.refreshMappings()
        panels = [
            ("ps3-platform-selector", AnyView(PlayerView(model: model).platformSelector.frame(width: 260))),
            ("ps3-library", AnyView(PlayerView(model: model).frame(width: 1180, height: 860))),
            ("ps3-settings", AnyView(PS3SettingsView(model: model))),
            ("ps3-controls", AnyView(PS3ControlsView(model: model))),
            ("ps3-diagnostics", AnyView(DiagnosticsView(model: model)))
        ]
    }
    let dark = CommandLine.arguments.contains("--dark")
    if dark { NSApplication.shared.appearance = NSAppearance(named: .darkAqua) }
    for (name, content) in panels {
        let host = NSHostingView(rootView: content.environment(\.colorScheme, dark ? .dark : .light).background(Color(nsColor: .windowBackgroundColor)))
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw CocoaError(.fileWriteUnknown) }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: directory.appendingPathComponent(name + ".png"))
        window.orderOut(nil)
    }
    print("Rendered \(panels.count) native panels without activating or showing a window")
}
