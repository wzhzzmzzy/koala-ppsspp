import Foundation

// Does not launch RPCS3 or modify its standard profile. Test-only fixtures use
// injected home URLs, never replace HOME in the real engine's environment.
func ps3StorageReport() throws -> Data {
    let engine = PS3Engine()
    let helper = Bundle.main.bundleURL.appendingPathComponent(PS3Engine.relativeExecutable)
    let report: [String: Any] = [
        "engine": "RPCS3", "version": PS3Engine.version, "executable": helper.path,
        "enginePresent": FileManager.default.isExecutableFile(atPath: helper.path),
        "supportedOS": PS3Engine.supported, "minimumMacOS": "15.0",
        "profile": engine.config.path, "cache": engine.cache.path,
        "checkArguments": try engine.arguments(for: .check),
        "inputOwner": engine.inputOwner, "standardProfileShared": true,
        "firmwareDetected": (try? engine.firmwareDescription()) != nil,
        "webRuntime": false, "emulationTested": false
    ]
    return try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
}

@MainActor func ps3LaunchReport() throws -> Data {
    let model = PlayerModel.shared
    guard model.store.paths.isolated else { throw PS3Error.invalid("Launch probe requires KOALA_DATA_DIR") }
    model.platform = .ps3
    model.startPS3(.check)
    if let error = model.error { throw PS3Error.invalid(error) }
    let deadline = Date().addingTimeInterval(10)
    while model.running, Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
    guard !model.running, model.error == nil, !model.pending else { throw PS3Error.invalid(model.error ?? "RPCS3 probe did not exit") }
    let output = try String(contentsOf: model.sessionRoot.appendingPathComponent("engine.log"), encoding: .utf8)
    guard output.contains("RPCS3 \(PS3Engine.version)") else { throw PS3Error.invalid("Unexpected engine version") }
    return try JSONSerialization.data(withJSONObject: ["passed": true, "launchThroughPlayerModel": true,
        "normalExitObserved": true, "uiOpened": false, "gamePerformanceMeasured": false], options: [.prettyPrinted, .sortedKeys])
}
