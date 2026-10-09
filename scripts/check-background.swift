import AppKit
import CoreGraphics
let pid = Int32(CommandLine.arguments[1])!
let app = NSRunningApplication(processIdentifier: pid)
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
let visible = windows.filter { ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid }.count
let report: [String: Any] = ["pid": pid, "active": app?.isActive ?? false, "visibleWindowCount": visible]
FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]))
if app?.isActive == true || visible > 0 { exit(1) }
