import AppKit
import SwiftUI

// Offscreen rendering only: no window is ordered front and no activation occurs.
@MainActor func renderPreviews(to directory: URL) throws {
    NSApplication.shared.setActivationPolicy(.prohibited)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let model = PlayerModel.shared
    model.preferences = PlayerPreferences(scale: 3)
    model.preferences.hud = 2
    var panels: [(String, AnyView)] = [
        ("settings-video", AnyView(PlayerSettingsView(model: model))),
        ("settings-audio", AnyView(PlayerSettingsView(model: model, tab: 1))),
        ("settings-hud", AnyView(PlayerSettingsView(model: model, tab: 2))),
        ("controls-keyboard", AnyView(ControlsView())),
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
    for (name, content) in panels {
        let host = NSHostingView(rootView: content.environment(\.colorScheme, .light).background(Color(nsColor: .windowBackgroundColor)))
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw CocoaError(.fileWriteUnknown) }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: directory.appendingPathComponent(name + ".png"))
        window.orderOut(nil)
    }
    print("Rendered \(panels.count) native panels without activating or showing a window")
}
