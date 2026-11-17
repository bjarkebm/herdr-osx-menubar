import Foundation

/// Client for the herdr TUI's socket API, as upstream HerdrBar used it. Every
/// call is a fresh short-lived connection; herdr answers one response per
/// connection. Upstream got live agent state from plugin hooks; this fork
/// installs none, so the app polls `session.snapshot` instead.
enum HerdrTUIClient {

    private static func call(_ method: String, _ params: [String: Any] = [:],
                             timeout: TimeInterval = 3) -> [String: Any]? {
        let body: [String: Any] = ["id": "herdr-osx-menubar", "method": method, "params": params]
        guard let reply = UnixSocket.request(path: Config.current.tuiSocket, json: body, timeout: timeout)
        else { return nil }
        if reply["error"] != nil { return nil }
        return reply["result"] as? [String: Any]
    }

    /// Is a herdr server accepting connections right now?
    static func isRunning() -> Bool {
        call("ping", timeout: 1) != nil
    }

    /// `timeout` is kept short for menu-building calls: the socket is local and
    /// answers in microseconds, but the menu must never stall behind a wedged
    /// server.
    static func snapshot(timeout: TimeInterval = 3) -> Snapshot? {
        guard let result = call("session.snapshot", timeout: timeout),
              let snap = result["snapshot"] as? [String: Any] else { return nil }

        let workspaces = (snap["workspaces"] as? [[String: Any]] ?? []).compactMap {
            ws -> WorkspaceSnapshot? in
            guard let id = ws["workspace_id"] as? String else { return nil }
            let worktree = ws["worktree"] as? [String: Any]
            return WorkspaceSnapshot(
                workspaceId: id,
                label: ws["label"] as? String ?? id,
                number: ws["number"] as? Int ?? Int.max,
                repoRoot: worktree?["repo_root"] as? String)
        }

        let panes = (snap["panes"] as? [[String: Any]] ?? []).compactMap {
            p -> PaneSnapshot? in
            guard let id = p["pane_id"] as? String,
                  let wsId = p["workspace_id"] as? String else { return nil }
            return PaneSnapshot(
                paneId: id,
                workspaceId: wsId,
                cwd: p["cwd"] as? String,
                agent: p["agent"] as? String,
                displayAgent: p["display_agent"] as? String,
                agentStatus: p["agent_status"] as? String ?? "unknown")
        }

        let tabs = (snap["tabs"] as? [[String: Any]] ?? []).compactMap {
            t -> TabSnapshot? in
            guard let id = t["tab_id"] as? String,
                  let wsId = t["workspace_id"] as? String else { return nil }
            let number = t["number"] as? Int ?? Int.max
            return TabSnapshot(
                tabId: id,
                workspaceId: wsId,
                label: t["label"] as? String ?? String(number),
                number: number)
        }

        let agents = (snap["agents"] as? [[String: Any]] ?? []).compactMap {
            a -> AgentSnapshot? in
            guard let paneId = a["pane_id"] as? String,
                  let wsId = a["workspace_id"] as? String else { return nil }
            return AgentSnapshot(
                paneId: paneId,
                workspaceId: wsId,
                tabId: a["tab_id"] as? String,
                agent: (a["display_agent"] as? String) ?? (a["agent"] as? String) ?? "agent",
                status: a["agent_status"] as? String ?? "unknown",
                focused: a["focused"] as? Bool ?? false,
                cwd: a["cwd"] as? String,
                title: (a["terminal_title_stripped"] as? String)
                    ?? (a["terminal_title"] as? String))
        }

        return Snapshot(
            workspaces: workspaces, panes: panes, tabs: tabs, agents: agents,
            focusedWorkspaceId: snap["focused_workspace_id"] as? String)
    }

    /// Create a workspace rooted at `path` and focus it. Returns false when the
    /// server is not reachable, so the caller can fall back to launching herdr.
    @discardableResult
    static func createWorkspace(cwd: String, label: String?) -> Bool {
        var params: [String: Any] = ["cwd": cwd, "focus": true]
        if let label { params["label"] = label }
        return call("workspace.create", params) != nil
    }

    @discardableResult
    static func focusWorkspace(_ workspaceId: String) -> Bool {
        call("workspace.focus", ["workspace_id": workspaceId]) != nil
    }

    /// Focus one agent, exactly as selecting its row inside herdr does. The
    /// target is the agent's `pane_id` — herdr resolves no other form (a
    /// workspace label or a bare "claude" both come back `agent_not_found`).
    @discardableResult
    static func focusAgent(paneId: String) -> Bool {
        call("agent.focus", ["target": paneId]) != nil
    }
}
