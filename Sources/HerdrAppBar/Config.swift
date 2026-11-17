import Foundation

/// User-editable settings at `~/Library/Application Support/dev.herdr.appbar/config.json`.
/// Written on first launch so the file is discoverable and self-documenting.
struct Config {
    /// Absolute paths to the two CLIs. A GUI app inherits a minimal PATH that
    /// never contains `~/.local/bin`, so they are always called by full path.
    var herdrAppBinary: String = NSHomeDirectory() + "/.local/bin/herdr-app"
    var hcBinary: String = NSHomeDirectory() + "/.local/bin/hc"
    var appBundleId: String = "dev.herdr.app"

    /// The herdr TUI: its API socket, the binary a new terminal window runs,
    /// and the terminal app that window opens in. The socket path is fixed
    /// rather than read from `HERDR_SOCKET_PATH`: herdr-app terminals inherit
    /// stale TUI variables, and a GUI app should not trust its environment.
    var tuiSocket: String = NSHomeDirectory() + "/.config/herdr/herdr.sock"
    var herdrBinary: String = ""
    var terminalBundleId: String = "com.apple.Terminal"

    /// How long the icon keeps blinking for a waiting agent before it settles
    /// to the static badge. `0` means "keep blinking until clicked".
    var blinkTimeoutSeconds: Int = Config.defaultBlinkTimeout

    static let defaultBlinkTimeout = 180

    /// The choices offered in the menu, in order.
    static let blinkTimeoutChoices: [(title: String, seconds: Int)] = [
        ("1 minute", 60),
        ("3 minutes", 180),
        ("10 minutes", 600),
        ("Until clicked", 0),
    ]

    /// Read once by the CLI wrappers, which have no Config instance to hand.
    static var current = Config.load()

    static func load() -> Config {
        var config = Config()
        if let data = FileManager.default.contents(atPath: Paths.configFile),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let b = json["herdrAppBinary"] as? String, !b.isEmpty { config.herdrAppBinary = b }
            if let b = json["hcBinary"] as? String, !b.isEmpty { config.hcBinary = b }
            if let b = json["appBundleId"] as? String, !b.isEmpty { config.appBundleId = b }
            if let p = json["tuiSocket"] as? String, !p.isEmpty { config.tuiSocket = p }
            if let b = json["herdrBinary"] as? String { config.herdrBinary = b }
            if let t = json["terminalBundleId"] as? String, !t.isEmpty { config.terminalBundleId = t }
            if let t = json["blinkTimeoutSeconds"] as? Int, t >= 0 {
                config.blinkTimeoutSeconds = t
            }
        }
        if config.herdrBinary.isEmpty { config.herdrBinary = Config.locateHerdr() }
        return config
    }

    func save() {
        Paths.ensureSupportDir()
        let json: [String: Any] = [
            "herdrAppBinary": herdrAppBinary,
            "hcBinary": hcBinary,
            "appBundleId": appBundleId,
            "tuiSocket": tuiSocket,
            "herdrBinary": herdrBinary,
            "terminalBundleId": terminalBundleId,
            "blinkTimeoutSeconds": blinkTimeoutSeconds,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: json,
                                                     options: [.prettyPrinted, .sortedKeys])
        else { return }
        try? data.write(to: URL(fileURLWithPath: Paths.configFile))
        Config.current = self
    }

    /// A GUI process gets PATH=/usr/bin:/bin:/usr/sbin:/sbin, which never
    /// contains herdr, so check the usual install roots.
    private static func locateHerdr() -> String {
        let candidates = [
            "/opt/homebrew/bin/herdr",
            "/usr/local/bin/herdr",
            NSHomeDirectory() + "/.local/bin/herdr",
            "/usr/bin/herdr",
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        // Last resort: the login shell that runs the launch script resolves it.
        return "herdr"
    }
}
