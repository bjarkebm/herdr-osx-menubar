import Foundation

/// herdrappbar-open — the command-line entry point into a running HerdrAppBar.
///
/// Two modes:
///
///   herdrappbar-open <path>...   Open paths in Herdr as new spaces. Starts HerdrAppBar if needed.
///
///   herdrappbar-open --picker    Ask HerdrAppBar to show its folder picker.
///
///   herdrappbar-open --panel     Ask HerdrAppBar to show its agents panel.
///
///   herdrappbar-open --status    Print HerdrAppBar's current state as JSON.
///
/// This is a compiled binary rather than a `nc`/`python` shell-out on purpose:
/// shelling out to an interpreter
/// risks both latency and, on a machine without Command Line Tools, a developer
/// tools install prompt.

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("herdrappbar-open: \(message)\n".utf8))
    exit(1)
}

/// The enclosing .app, derived from this binary's own location inside
/// `HerdrAppBar.app/Contents/MacOS/`, so a relocated bundle still starts itself.
func enclosingAppBundle() -> String? {
    let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    let bundle = executable            // .../Contents/MacOS/herdrappbar-open
        .deletingLastPathComponent()   // .../Contents/MacOS
        .deletingLastPathComponent()   // .../Contents
        .deletingLastPathComponent()   // .../HerdrAppBar.app
    return bundle.pathExtension == "app" ? bundle.path : nil
}

func appIsListening() -> Bool {
    guard let probe = UnixSocket.connect(path: Paths.barSocket, timeout: 0.5) else { return false }
    close(probe)
    return true
}

/// Start HerdrAppBar in the background and wait for it to claim its socket.
func launchApp() -> Bool {
    guard let bundle = enclosingAppBundle() else { return false }

    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    // -g: do not steal focus; the terminal herdr opens should come forward.
    task.arguments = ["-g", bundle]
    try? task.run()
    task.waitUntilExit()

    for _ in 0 ..< 30 {
        if appIsListening() { return true }
        usleep(100_000)
    }
    return false
}

// MARK: - Entry

let arguments = Array(CommandLine.arguments.dropFirst())

if arguments.first == "--status" {
    guard appIsListening() else { fail("HerdrAppBar is not running") }
    guard let fd = UnixSocket.connect(path: Paths.barSocket, timeout: 3) else {
        fail("could not connect to HerdrAppBar")
    }
    defer { close(fd) }
    var request = try! JSONSerialization.data(withJSONObject: ["kind": "status"])
    request.append(0x0A)
    guard UnixSocket.writeAll(fd, request), let reply = UnixSocket.readLine(fd) else {
        fail("no answer from HerdrAppBar")
    }
    FileHandle.standardOutput.write(reply)
    FileHandle.standardOutput.write(Data("\n".utf8))
    exit(0)
}

if arguments.first == "--panel" {
    guard appIsListening() || launchApp() else {
        fail("HerdrAppBar is not running and could not be started")
    }
    exit(UnixSocket.send(path: Paths.barSocket, json: ["kind": "panel"]) ? 0 : 1)
}

if arguments.first == "--picker" {
    guard appIsListening() || launchApp() else {
        fail("HerdrAppBar is not running and could not be started")
    }
    exit(UnixSocket.send(path: Paths.barSocket, json: ["kind": "picker"]) ? 0 : 1)
}

let paths = arguments.filter { !$0.isEmpty && !$0.hasPrefix("--") }
guard !paths.isEmpty else {
    fail("usage: herdrappbar-open <path> [path...]"
        + "  |  herdrappbar-open --panel | --picker | --status")
}

guard appIsListening() || launchApp() else {
    fail("HerdrAppBar is not running and could not be started")
}

var failures = 0
for path in paths {
    let absolute = URL(fileURLWithPath: path).standardizedFileURL.path
    if !UnixSocket.send(path: Paths.barSocket, json: ["kind": "open", "path": absolute]) {
        FileHandle.standardError.write(Data("herdrappbar-open: could not send \(absolute)\n".utf8))
        failures += 1
    }
}

exit(failures == 0 ? 0 : 1)
