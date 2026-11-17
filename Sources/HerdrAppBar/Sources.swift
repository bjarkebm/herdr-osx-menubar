import Foundation

/// The two herdrs the bar can show at once: the herdr-app desktop app and the
/// herdr TUI server. Everything the panel and the icon see is merged from
/// both, with every id prefixed by its source so that actions can be routed
/// back and ids from the two never collide.
enum HerdrSource: String, CaseIterable {
    case app
    case tui

    /// Short tag drawn next to each workspace header.
    var title: String {
        switch self {
        case .app: return "Herdr"
        case .tui: return "Herdr TUI"
        }
    }

    /// herdr-app first.
    var rank: Int { self == .app ? 0 : 1 }

    func tag(_ id: String) -> String { rawValue + "/" + id }

    /// Splits a tagged id back into its source and the id that source knows.
    static func untag(_ id: String) -> (source: HerdrSource, id: String)? {
        guard let slash = id.firstIndex(of: "/"),
              let source = HerdrSource(rawValue: String(id[..<slash])) else { return nil }
        return (source, String(id[id.index(after: slash)...]))
    }

    /// A raw snapshot of this source, or nil when it is not running.
    func snapshot(timeout: TimeInterval) -> Snapshot? {
        switch self {
        case .app: return HerdrClient.snapshot(timeout: timeout)
        case .tui: return HerdrTUIClient.snapshot(timeout: timeout)
        }
    }
}

extension WorkspaceSnapshot {
    /// Orders workspaces by source, then by that source's own ordering.
    var sortKey: Int { source.rank * 1_000_000 + min(number, 999_999) }
}

extension Snapshot {

    func tagged(_ source: HerdrSource) -> Snapshot {
        var copy = self
        copy.workspaces = workspaces.map {
            var ws = WorkspaceSnapshot(workspaceId: source.tag($0.workspaceId), label: $0.label,
                                       number: $0.number, repoRoot: $0.repoRoot)
            ws.source = source
            return ws
        }
        copy.panes = panes.map {
            PaneSnapshot(paneId: source.tag($0.paneId), workspaceId: source.tag($0.workspaceId),
                         cwd: $0.cwd, agent: $0.agent, displayAgent: $0.displayAgent,
                         agentStatus: $0.agentStatus)
        }
        copy.tabs = tabs.map {
            TabSnapshot(tabId: source.tag($0.tabId), workspaceId: source.tag($0.workspaceId),
                        label: $0.label, number: $0.number)
        }
        copy.agents = agents.map {
            AgentSnapshot(paneId: source.tag($0.paneId), workspaceId: source.tag($0.workspaceId),
                          tabId: $0.tabId.map(source.tag), agent: $0.agent, status: $0.status,
                          focused: $0.focused, cwd: $0.cwd, title: $0.title)
        }
        copy.focusedWorkspaceIds = Set(focusedWorkspaceIds.map(source.tag))
        copy.sources = [source]
        return copy
    }

    /// Ask every source; one that is not running is skipped. Nil only when
    /// none of them answers. The two are read concurrently so a slow
    /// herdr-app CLI does not delay the TUI socket, or the reverse.
    static func gather(timeout: TimeInterval) -> Snapshot? {
        let sources = HerdrSource.allCases
        var parts = [Snapshot?](repeating: nil, count: sources.count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: sources.count) { index in
            let part = sources[index].snapshot(timeout: timeout)?.tagged(sources[index])
            lock.lock()
            parts[index] = part
            lock.unlock()
        }
        let answered = parts.compactMap { $0 }
        guard var merged = answered.first else { return nil }
        for part in answered.dropFirst() {
            merged.workspaces += part.workspaces
            merged.panes += part.panes
            merged.tabs += part.tabs
            merged.agents += part.agents
            merged.focusedWorkspaceIds.formUnion(part.focusedWorkspaceIds)
            merged.sources += part.sources
        }
        return merged
    }
}
