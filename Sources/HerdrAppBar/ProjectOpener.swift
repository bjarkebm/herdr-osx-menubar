import AppKit
import Foundation

/// The single path every "open this project" and "focus this agent" entry
/// point funnels through. Agents and workspaces are routed to the herdr their
/// tagged id came from; a new folder goes to herdr-app when it is running,
/// else to the TUI.
enum ProjectOpener {

    /// Resolve `path` to a directory (a file opens its parent), then hand it to
    /// herdr. Socket and CLI work happens off the main thread; AppKit calls hop
    /// back.
    static func open(path: String, config: Config, completion: (() -> Void)? = nil) {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDirectory) else {
            NSSound.beep()
            completion?()
            return
        }
        let directory = isDirectory.boolValue
            ? path
            : (path as NSString).deletingLastPathComponent
        let label = (directory as NSString).lastPathComponent

        DispatchQueue.global(qos: .userInitiated).async {
            if HerdrClient.isRunning() {
                let created = HerdrClient.createWorkspace(cwd: directory, label: label)
                DispatchQueue.main.async {
                    if created {
                        AppHost.bringToFront()
                    } else {
                        AppHost.launchHerdr(cwd: directory, config: config)
                    }
                    completion?()
                }
                return
            }

            if HerdrTUIClient.isRunning(),
               HerdrTUIClient.createWorkspace(cwd: directory, label: label) {
                DispatchQueue.main.async {
                    // The workspace exists and is focused; make sure something
                    // is actually displaying it.
                    if TerminalHost.hasVisibleClient() {
                        TerminalHost.bringToFront()
                    } else {
                        // Attaching with no cwd lands on the focused workspace.
                        TerminalHost.launchHerdr(cwd: nil, config: config)
                        TerminalHost.invalidateHostCache()
                    }
                    completion?()
                }
                return
            }

            // Neither is up: start herdr-app in the folder.
            DispatchQueue.main.async {
                AppHost.launchHerdr(cwd: directory, config: config)
                completion?()
            }
        }
    }

    /// Focus one agent and make sure it is on screen — the agents panel's row
    /// click, and the menu's waiting rows.
    ///
    /// `agent.focus` fails for a pane herdr no longer tracks as an agent (the
    /// agent exited between the snapshot and the click), so fall back to
    /// focusing the workspace, which at least lands the user in the right
    /// project.
    static func focusAgent(paneId: String, workspaceId: String, config: Config) {
        guard let pane = HerdrSource.untag(paneId),
              let workspace = HerdrSource.untag(workspaceId) else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            switch pane.source {
            case .app:
                let ok = HerdrClient.focusAgent(paneId: pane.id)
                    || HerdrClient.focusWorkspace(workspace.id)
                DispatchQueue.main.async { showApp(ok, config: config) }
            case .tui:
                let ok = HerdrTUIClient.focusAgent(paneId: pane.id)
                    || HerdrTUIClient.focusWorkspace(workspace.id)
                DispatchQueue.main.async { showTUI(ok, config: config) }
            }
        }
    }

    /// Focus a workspace and show it — the agents panel's workspace headers.
    static func focusWorkspace(_ workspaceId: String, config: Config) {
        guard let workspace = HerdrSource.untag(workspaceId) else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            switch workspace.source {
            case .app:
                let ok = HerdrClient.focusWorkspace(workspace.id)
                DispatchQueue.main.async { showApp(ok, config: config) }
            case .tui:
                let ok = HerdrTUIClient.focusWorkspace(workspace.id)
                DispatchQueue.main.async { showTUI(ok, config: config) }
            }
        }
    }

    private static func showApp(_ ok: Bool, config: Config) {
        if AppHost.hasVisibleClient() {
            AppHost.bringToFront()
        } else if ok {
            AppHost.launchHerdr(cwd: nil, config: config)
        }
    }

    private static func showTUI(_ ok: Bool, config: Config) {
        if TerminalHost.hasVisibleClient() {
            TerminalHost.bringToFront()
        } else if ok {
            TerminalHost.launchHerdr(cwd: nil, config: config)
            TerminalHost.invalidateHostCache()
        }
    }

    /// Folder picker used by the menu and `herdrappbar-open --picker`.
    static func chooseFolder(config: Config) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open in Herdr"
        panel.message = "Choose a folder to open as a new Herdr space"

        // An accessory-mode app has no windows, so the panel needs the app
        // pulled forward or it opens behind whatever is frontmost.
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(path: url.path, config: config)
    }
}
