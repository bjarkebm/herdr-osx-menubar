import Foundation

/// Follows `hc events --json` and calls `onChange` (on the main queue) for
/// every fact change herdr-core reports — agent status, titles, terminals
/// starting or ending. It stands in for the TUI's plugin hooks, which herdr-app
/// does not have.
///
/// The stream carries no space/tab layout, so the app still polls
/// `herdr-app ls` on a short beat; this just makes status changes show up
/// without waiting for the next poll. If `hc events` exits (herdr-core not
/// running, or restarted), it is restarted after a pause.
final class HerdrEvents {

    var onChange: (() -> Void)?

    private let hcBinary: String
    private var task: Process?
    private var buffer = Data()
    private var stopped = false
    private let queue = DispatchQueue(label: "dev.herdr.appbar.hc-events")

    private static let restartDelay: TimeInterval = 5

    init(hcBinary: String) {
        self.hcBinary = hcBinary
    }

    func start() {
        queue.async { [weak self] in self?.launch() }
    }

    func stop() {
        queue.sync {
            stopped = true
            task?.terminate()
            task = nil
        }
    }

    private func launch() {
        guard !stopped else { return }
        guard FileManager.default.isExecutableFile(atPath: hcBinary) else {
            scheduleRestart()
            return
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: hcBinary)
        task.arguments = ["events", "--json"]
        let out = Pipe()
        task.standardOutput = out
        task.standardError = FileHandle.nullDevice
        task.standardInput = FileHandle.nullDevice

        out.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard let self else { return }
            self.queue.async { self.consume(chunk) }
        }
        task.terminationHandler = { [weak self] _ in
            out.fileHandleForReading.readabilityHandler = nil
            guard let self else { return }
            self.queue.async {
                self.task = nil
                self.buffer.removeAll()
                self.scheduleRestart()
            }
        }

        do {
            try task.run()
            self.task = task
        } catch {
            scheduleRestart()
        }
    }

    private func scheduleRestart() {
        guard !stopped else { return }
        queue.asyncAfter(deadline: .now() + Self.restartDelay) { [weak self] in
            guard let self, self.task == nil else { return }
            self.launch()
        }
    }

    private func consume(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        buffer.append(chunk)

        var changed = false
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex ..< newline]
            buffer.removeSubrange(buffer.startIndex ... newline)
            if isChange(line) { changed = true }
        }
        if changed {
            DispatchQueue.main.async { [weak self] in self?.onChange?() }
        }
    }

    /// Heartbeats keep the stream alive and say nothing; everything else (the
    /// initial full listing, and each `event`) is worth a refresh.
    private func isChange(_ line: Data) -> Bool {
        guard !line.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any]
        else { return false }
        return object["method"] as? String != "heartbeat"
    }
}
