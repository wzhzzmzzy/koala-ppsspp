import Foundation

// Packaging probe. Runs before any app window is constructed.
func ps2StorageReport() throws -> Data {
    let paths = AppPaths()
    try paths.prepare()
    let engine = PS2Engine(paths: paths)
    guard let defaults = Bundle.main.url(forResource: "ARMSX2-defaults", withExtension: "ini") else { throw PS2Error.invalid("Missing PS2 defaults") }
    try engine.prepare(defaults: defaults)
    if let i = CommandLine.arguments.firstIndex(of: "--import-bios"), CommandLine.arguments.indices.contains(i+1) {
        _ = try engine.importBIOS(URL(fileURLWithPath: CommandLine.arguments[i+1]))
    }
    let ini = try engine.read()
    let bios = try engine.selectedBIOS()
    let helper = Bundle.main.bundleURL.appendingPathComponent(PS2Engine.relativeExecutable)
    var missingBIOSRejected = false
    if bios == nil {
        do { _ = try engine.arguments(for: .bios, log: engine.logs) }
        catch { missingBIOSRejected = true }
    }
    let report: [String: Any] = [
        "engine": "ARMSX2", "version": PS2Engine.version, "executable": helper.path,
        "enginePresent": FileManager.default.isExecutableFile(atPath: helper.path),
        "data": engine.data.path, "config": engine.config.path, "cache": engine.cache.path, "logs": engine.logs.path,
        "biosPresent": bios != nil, "biosDescription": bios?.description ?? "", "missingBIOSRejected": missingBIOSRejected,
        "checkArguments": try engine.arguments(for: .check, log: engine.logs.appendingPathComponent("probe.log")),
        "renderer": ini.value("EmuCore/GS", "Renderer") ?? "", "renderScale": PS2Options(ini).scale,
        "inputBindingCount": PS2Mappings.snapshot(ini).actions.filter { !$0.bindings.isEmpty }.count,
        "webRuntime": false, "gamePerformanceMeasured": false
    ]
    return try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
}

@MainActor func platformIntegrationReport() throws -> Data {
    let model = PlayerModel.shared
    guard model.store.paths.isolated, model.games.isEmpty,
          !FileManager.default.fileExists(atPath: model.store.paths.engineConfig.appendingPathComponent("controls.ini").path) else {
        throw PS2Error.invalid("Platform integration check requires a fresh KOALA_DATA_DIR")
    }
    let controls = model.store.paths.engineConfig.appendingPathComponent("controls.ini")
    try "[ControlMapping]\nCross = 1-54\n".write(to: controls, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: controls) }
    model.platform = .psp; model.refreshMappings()
    let first = model.mappings
    guard first?.actions.first?.name == "Cross" else { throw PS2Error.invalid("PSP mapping fixture not loaded") }
    model.platform = .ps2; model.refreshMappings()
    guard model.mappings?.actions.count == 24 else { throw PS2Error.invalid("PS2 mapping not loaded") }
    model.startPS2(.bios)
    guard !model.running, model.error?.contains("BIOS") == true else { throw PS2Error.invalid("Missing BIOS was not rejected by launcher") }
    model.error = nil
    let diagnostics = try JSONSerialization.jsonObject(with: model.diagnosticData()) as! [String:Any]
    guard (diagnostics["engine"] as? String)?.hasPrefix("ARMSX2") == true,
          (diagnostics["preferences"] as? [String:Any])?["renderer"] != nil else { throw PS2Error.invalid("Wrong PS2 diagnostic settings") }
    model.platform = .ps3; model.refreshMappings()
    guard model.mappings == nil, model.settingsPanel == .ps3 else { throw PS3Error.invalid("PS3 must not display PSP/PS2 mappings") }
    let ps3Diagnostics = try JSONSerialization.jsonObject(with: model.diagnosticData()) as! [String: Any]
    guard (ps3Diagnostics["engine"] as? String)?.hasPrefix("RPCS3") == true,
          ps3Diagnostics["requestedVulkanDriver"] == nil,
          (ps3Diagnostics["preferences"] as? [String: Any])?["inputOwner"] != nil else { throw PS3Error.invalid("PS3 diagnostics contain another engine's settings") }
    model.platform = .psp; model.refreshMappings()
    guard model.mappings == first else { throw PS2Error.invalid("PSP mapping cache did not survive platform roundtrip") }
    return try JSONSerialization.data(withJSONObject: ["passed":true, "platformRoundtrip":true, "missingBIOSBlockedBeforeProcess":true,
        "correctPS2Diagnostics":true, "uiOpened":false], options:[.prettyPrinted,.sortedKeys])
}
