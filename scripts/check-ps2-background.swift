import AppKit
import CoreGraphics

// Checks only metadata/configuration startup. Never boots a BIOS, game, render
// window or full screen. Scratch data must be independent of the real library.
let app = URL(fileURLWithPath: CommandLine.arguments[1])
let scratch = URL(fileURLWithPath: CommandLine.arguments[2])
try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
var environment = ProcessInfo.processInfo.environment
for key in environment.keys where key.hasPrefix("KOALA_") || key.hasPrefix("XDG_") { environment.removeValue(forKey:key) }
environment["KOALA_DATA_DIR"] = scratch.appendingPathComponent("data").path
environment["QT_MAC_DISABLE_FOREGROUND_APPLICATION_TRANSFORM"] = "1"
var samples = 0
var results: [[String:Any]] = []
func run(_ executable: URL, _ arguments: [String], name: String) throws -> Data {
    let out = scratch.appendingPathComponent(name+".stdout")
    let err = scratch.appendingPathComponent(name+".stderr")
    FileManager.default.createFile(atPath: out.path, contents: nil)
    FileManager.default.createFile(atPath: err.path, contents: nil)
    let stdout = try FileHandle(forWritingTo: out), stderr = try FileHandle(forWritingTo: err)
    defer { try? stdout.close(); try? stderr.close() }
    let process = Process(); process.executableURL = executable; process.arguments = arguments
    process.environment = environment; process.standardOutput = stdout; process.standardError = stderr
    let start = Date(); try process.run()
    while process.isRunning {
        let child = NSRunningApplication(processIdentifier: process.processIdentifier)
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let visible = windows.filter { ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == process.processIdentifier }.count
        guard child?.isActive != true && visible == 0 else { process.terminate(); fatalError("Unexpected active/visible test process") }
        guard Date().timeIntervalSince(start) < 30 else { process.terminate(); fatalError("Configuration startup timed out") }
        samples += 1; Thread.sleep(forTimeInterval: 0.01)
    }
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw NSError(domain:"PS2Probe",code:Int(process.terminationStatus),userInfo:[NSLocalizedDescriptionKey:try String(contentsOf:err,encoding:.utf8)]) }
    results.append(["operation":name, "seconds":Date().timeIntervalSince(start), "exitCode":process.terminationStatus])
    return try Data(contentsOf: out)
}
let launcher = app.appendingPathComponent("Contents/MacOS/KoalaPSP")
_ = try run(launcher, ["--platform-check"], name:"platform-roundtrip")
let data = try run(launcher, ["--ps2-report"], name:"launcher-config")
let report = try JSONSerialization.jsonObject(with:data) as! [String:Any]
assert(report["missingBIOSRejected"] as? Bool == true && report["enginePresent"] as? Bool == true)
let helper = URL(fileURLWithPath:report["executable"] as! String)
_ = try run(helper, report["checkArguments"] as! [String], name:"armsx2-testconfig")
_ = try run(launcher, ["--ps2-report"], name:"launcher-reopen")
let result: [String:Any] = ["passed":true,"samples":samples,"active":false,"visibleWindowCount":0,"fullscreenTested":false,"emulationTested":false,"operations":results]
let json = try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys])
try json.write(to:scratch.appendingPathComponent("result.json"))
FileHandle.standardOutput.write(json)
