import AppKit
import Foundation

/// The Herdr desktop app as a window to bring forward or launch.
///
/// The TUI version walked the process tree to find whichever terminal hosted
/// the herdr client; herdr-app is its own GUI app, so that reduces to looking
/// it up by bundle identifier. Activation still goes through
/// `NSRunningApplication` / LaunchServices, so no automation permission is
/// needed.
enum TerminalHost {

    static func hostApplication(useCache: Bool = true) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(
            withBundleIdentifier: Config.current.appBundleId
        ).first { !$0.isTerminated }
    }

    static func invalidateHostCache() {}

    /// True when the Herdr app is running, so there is a window to go back to.
    static func hasVisibleClient() -> Bool { hostApplication() != nil }

    static func isHostFrontmost() -> Bool {
        guard let host = hostApplication() else { return false }
        return NSWorkspace.shared.frontmostApplication?.processIdentifier == host.processIdentifier
    }

    @discardableResult
    static func bringToFront() -> Bool {
        openApp()
        return true
    }

    /// Open the Herdr window; with `cwd`, also make a space there once the
    /// window is up and answering.
    static func launchHerdr(cwd: String?, config: Config) {
        openApp()
        guard let cwd else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            for _ in 0 ..< 40 {
                if HerdrClient.isRunning() {
                    HerdrClient.createWorkspace(
                        cwd: cwd, label: (cwd as NSString).lastPathComponent)
                    return
                }
                usleep(250_000)
            }
        }
    }

    /// `open -b` both launches Herdr and brings an existing window forward.
    private static func openApp() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-b", Config.current.appBundleId]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
    }
}
