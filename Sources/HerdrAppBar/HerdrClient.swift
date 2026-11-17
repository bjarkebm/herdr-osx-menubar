import Foundation

/// A pane as reported by `herdr-app ls`.
struct PaneSnapshot {
    let paneId: String
    let workspaceId: String
    let cwd: String?
    let agent: String?
    let displayAgent: String?
    let agentStatus: String

    /// What to call the agent in the menu: herdr's own display name when it has
    /// one, otherwise the raw kind ("claude", "codex", ...).
    var agentName: String { displayAgent ?? agent ?? "agent" }
}

/// A workspace as reported by `herdr-app ls`.
struct WorkspaceSnapshot {
    let workspaceId: String
    let label: String
    /// herdr's own ordering of the workspace list.
    let number: Int
    /// Repo root for worktree-backed workspaces; the project path we prefer.
    let repoRoot: String?
    /// Which herdr this came from; set when sources are merged.
    var source: HerdrSource = .app
}

/// A tab as reported by `herdr-app ls`. Only its label is interesting here:
/// it is what distinguishes two agents in the same project.
struct TabSnapshot {
    let tabId: String
    let workspaceId: String
    let label: String
    let number: Int

    /// herdr labels a tab with its own number until the user renames it, and a
    /// bare "3" says nothing in a list — so only a real name is worth showing.
    var isNamed: Bool { label != String(number) && !label.isEmpty }
}

/// An entry of the snapshot's `agents` array — herdr's own agent list, the same
/// data its in-terminal agents panel is drawn from.
struct AgentSnapshot {
    let paneId: String
    let workspaceId: String
    let tabId: String?
    let agent: String
    /// `idle`, `working`, `blocked`, `done` or `unknown`.
    let status: String
    /// True for the one agent herdr currently has focused.
    let focused: Bool
    let cwd: String?
    /// The pane's terminal title with herdr's status glyph stripped — what the
    /// agent is working on, and the panel's most useful line of text.
    let title: String?
}

/// One row of the agents panel: an agent, resolved against the workspace and
/// tab labels it belongs to.
struct AgentRow: Equatable {
    let paneId: String
    let workspaceId: String
    /// Project name — the row's primary text.
    let project: String
    /// Tab name, when the user named it. Shown dimmed after the project.
    let tab: String?
    let agent: String
    let status: String
    let focused: Bool
    let cwd: String?

    /// Status as a word, for the row's secondary line.
    var statusLabel: String { status == "unknown" ? "" : status }
}

struct Snapshot {
    var workspaces: [WorkspaceSnapshot]
    var panes: [PaneSnapshot]
    var tabs: [TabSnapshot]
    var agents: [AgentSnapshot]
    /// What each herdr is showing right now — the panel marks it in bold.
    var focusedWorkspaceIds: Set<String>
    /// The sources that answered.
    var sources: [HerdrSource] = []

    init(workspaces: [WorkspaceSnapshot], panes: [PaneSnapshot], tabs: [TabSnapshot],
         agents: [AgentSnapshot], focusedWorkspaceId: String?) {
        self.workspaces = workspaces
        self.panes = panes
        self.tabs = tabs
        self.agents = agents
        self.focusedWorkspaceIds = focusedWorkspaceId.map { [$0] } ?? []
    }

    func workspace(_ id: String) -> WorkspaceSnapshot? {
        workspaces.first { $0.workspaceId == id }
    }

    func tab(_ id: String?) -> TabSnapshot? {
        guard let id else { return nil }
        return tabs.first { $0.tabId == id }
    }

    /// Best-effort project directory for a workspace: the worktree repo root if
    /// herdr tracks one, else the cwd of its first pane that has one.
    func projectPath(for workspaceId: String) -> String? {
        if let root = workspace(workspaceId)?.repoRoot, !root.isEmpty { return root }
        return panes.first { $0.workspaceId == workspaceId && $0.cwd != nil }?.cwd
    }

    /// The agents panel's rows, in herdr's own order: by workspace, then by tab,
    /// then by pane — so a row never moves unless herdr's layout does.
    func agentRows() -> [AgentRow] {
        let workspaceOrder = Dictionary(
            workspaces.map { ($0.workspaceId, $0.sortKey) }, uniquingKeysWith: { a, _ in a })
        let tabOrder = Dictionary(
            tabs.map { ($0.tabId, $0.number) }, uniquingKeysWith: { a, _ in a })

        return agents
            .sorted {
                let leftWorkspace = workspaceOrder[$0.workspaceId] ?? Int.max
                let rightWorkspace = workspaceOrder[$1.workspaceId] ?? Int.max
                if leftWorkspace != rightWorkspace { return leftWorkspace < rightWorkspace }
                let leftTab = $0.tabId.flatMap { tabOrder[$0] } ?? Int.max
                let rightTab = $1.tabId.flatMap { tabOrder[$0] } ?? Int.max
                if leftTab != rightTab { return leftTab < rightTab }
                return $0.paneId < $1.paneId
            }
            .map { agent in
                let workspace = workspace(agent.workspaceId)
                let tab = tab(agent.tabId)
                return AgentRow(
                    paneId: agent.paneId,
                    workspaceId: agent.workspaceId,
                    project: workspace?.label ?? agent.workspaceId,
                    // Suppress a tab name that only repeats the project name.
                    tab: (tab?.isNamed == true && tab?.label != workspace?.label)
                        ? tab?.label : nil,
                    agent: agent.agent,
                    status: agent.status,
                    focused: agent.focused,
                    cwd: agent.cwd)
            }
    }
}


/// Runs a CLI by absolute path with a hard timeout. A GUI app's PATH does not
/// include `~/.local/bin`, so nothing here relies on PATH lookup.
enum CLI {
    struct Result {
        let status: Int32
        let stdout: Data
    }

    static func run(_ executable: String, _ arguments: [String],
                    timeout: TimeInterval = 3) -> Result? {
        guard FileManager.default.isExecutableFile(atPath: executable) else { return nil }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        let out = Pipe()
        task.standardOutput = out
        task.standardError = FileHandle.nullDevice
        task.standardInput = FileHandle.nullDevice

        let done = DispatchSemaphore(value: 0)
        task.terminationHandler = { _ in done.signal() }
        do { try task.run() } catch { return nil }

        // Drain stdout concurrently so a large reply cannot fill the pipe and
        // deadlock the child before it exits.
        var data = Data()
        let reader = DispatchQueue.global(qos: .userInitiated)
        let drained = DispatchSemaphore(value: 0)
        reader.async {
            data = out.fileHandleForReading.readDataToEndOfFile()
            drained.signal()
        }

        if done.wait(timeout: .now() + timeout) == .timedOut {
            task.terminate()
            _ = done.wait(timeout: .now() + 1)
            _ = drained.wait(timeout: .now() + 1)
            return nil
        }
        _ = drained.wait(timeout: .now() + 1)
        return Result(status: task.terminationStatus, stdout: data)
    }

    static func json(_ executable: String, _ arguments: [String],
                     timeout: TimeInterval = 3) -> [String: Any]? {
        guard let result = run(executable, arguments, timeout: timeout),
              result.status == 0 else { return nil }
        return try? JSONSerialization.jsonObject(with: result.stdout) as? [String: Any]
    }
}

/// Client for herdr-app. Reads state with `herdr-app ls` (spaces, tabs,
/// terminals and agent statuses) joined with `hc ls --json` (each terminal's
/// cwd), and drives the window with `herdr-app do <command>`.
///
/// Concept mapping from the TUI: workspace → space, tab → tab, pane/agent →
/// terminal. The `paneId` fields of the snapshot types carry the terminal
/// address (`t1n`), which is what herdr-app's focus commands take.
enum HerdrClient {

    private static var config: Config { Config.current }

    private static func herdrApp(_ arguments: [String],
                                 timeout: TimeInterval = 3) -> [String: Any]? {
        CLI.json(config.herdrAppBinary, arguments, timeout: timeout)
    }

    private static func doCommand(_ name: String, _ args: [String: Any]) -> Bool {
        guard let data = try? JSONSerialization.data(withJSONObject: args),
              let json = String(data: data, encoding: .utf8),
              let reply = herdrApp(["do", name, json]) else { return false }
        return reply["error"] == nil
    }

    /// Is a herdr-app window up and answering? `herdr-app ls` exits non-zero
    /// with "no Herdr window" when it is not.
    static func isRunning() -> Bool {
        herdrApp(["ls"], timeout: 1.5) != nil
    }

    static func snapshot(timeout: TimeInterval = 3) -> Snapshot? {
        guard let ls = herdrApp(["ls"], timeout: max(timeout, 1)) else { return nil }

        var cwds: [String: String] = [:]
        if let hc = CLI.json(config.hcBinary, ["ls", "--json"], timeout: max(timeout, 1)) {
            for t in hc["terminals"] as? [[String: Any]] ?? [] {
                if let address = t["address"] as? String, let cwd = t["cwd"] as? String {
                    cwds[address] = cwd
                }
            }
        }

        var workspaces: [WorkspaceSnapshot] = []
        var panes: [PaneSnapshot] = []
        var tabs: [TabSnapshot] = []
        var agents: [AgentSnapshot] = []
        var focusedWorkspaceId: String?

        for (spaceIndex, space) in (ls["spaces"] as? [[String: Any]] ?? []).enumerated() {
            guard let spaceId = space["id"] as? String else { continue }
            let folder = space["folder"] as? String
            let spaceName = (space["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? folder.map { ($0 as NSString).lastPathComponent } ?? spaceId
            let spaceActive = space["active"] as? Bool ?? false
            if spaceActive { focusedWorkspaceId = spaceId }

            workspaces.append(WorkspaceSnapshot(
                workspaceId: spaceId, label: spaceName, number: spaceIndex, repoRoot: folder))

            for (tabIndex, tab) in (space["tabs"] as? [[String: Any]] ?? []).enumerated() {
                guard let tabId = tab["id"] as? String else { continue }
                let number = tabIndex + 1
                let tabSnapshot = TabSnapshot(
                    tabId: tabId, workspaceId: spaceId,
                    label: tab["name"] as? String ?? String(number), number: number)
                tabs.append(tabSnapshot)
                let tabActive = tab["active"] as? Bool ?? false
                let terminals = tab["terminals"] as? [[String: Any]] ?? []
                let agentCount = terminals.filter(isAgent).count

                for terminal in terminals {
                    guard let address = terminal["terminal"] as? String else { continue }
                    let app = terminal["app"] as? String
                    let status = terminal["status"] as? String ?? "unknown"
                    let cwd = cwds[address]
                    panes.append(PaneSnapshot(
                        paneId: address, workspaceId: spaceId, cwd: cwd,
                        agent: app, displayAgent: app.map(displayName),
                        agentStatus: status))

                    guard isAgent(terminal) else { continue }
                    let name = (terminal["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                    // The tab's label is what herdr-app shows for an agent; a
                    // terminal's own name wins when several agents share a tab.
                    let title = name
                        ?? (tabSnapshot.isNamed && agentCount == 1 ? tabSnapshot.label : nil)
                        ?? terminalTitle(address)
                    agents.append(AgentSnapshot(
                        paneId: address, workspaceId: spaceId, tabId: tabId,
                        agent: app.map(displayName) ?? "agent",
                        status: status,
                        focused: spaceActive && tabActive && agentCount == 1,
                        cwd: cwd, title: title))
                }
            }
        }

        return Snapshot(
            workspaces: workspaces, panes: panes, tabs: tabs, agents: agents,
            focusedWorkspaceId: focusedWorkspaceId)
    }

    private static func isAgent(_ terminal: [String: Any]) -> Bool {
        terminal["app"] is String || terminal["status"] is String
    }

    /// "claude-code" → "Claude Code".
    private static func displayName(_ app: String) -> String {
        app.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    /// The terminal's own title, for an agent whose tab carries no name.
    private static func terminalTitle(_ address: String) -> String? {
        guard let info = CLI.json(config.hcBinary, ["get", address, "--json"], timeout: 1),
              let title = info["title"] as? String, !title.isEmpty else { return nil }
        return title
    }

    /// Make a space rooted at `cwd`; herdr-app shows it at once.
    @discardableResult
    static func createWorkspace(cwd: String, label: String?) -> Bool {
        var args: [String: Any] = ["folder": cwd]
        if let label { args["name"] = label }
        return doCommand("space.new", args)
    }

    @discardableResult
    static func focusWorkspace(_ workspaceId: String) -> Bool {
        doCommand("space.select", ["id": workspaceId])
    }

    /// Show one agent. `agent.focus` takes the terminal address; `pane.focus`
    /// covers a terminal that has stopped being an agent since the snapshot.
    @discardableResult
    static func focusAgent(paneId: String) -> Bool {
        doCommand("agent.focus", ["terminal": paneId])
            || doCommand("pane.focus", ["terminal": paneId])
    }
}
