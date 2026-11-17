import Foundation

/// User-editable settings at `~/Library/Application Support/dev.herdr.appbar/config.json`.
/// Written on first launch so the file is discoverable and self-documenting.
struct Config {
    /// Absolute paths to the two CLIs. A GUI app inherits a minimal PATH that
    /// never contains `~/.local/bin`, so they are always called by full path.
    var herdrAppBinary: String = NSHomeDirectory() + "/.local/bin/herdr-app"
    var hcBinary: String = NSHomeDirectory() + "/.local/bin/hc"
    var appBundleId: String = "dev.herdr.app"

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
            if let t = json["blinkTimeoutSeconds"] as? Int, t >= 0 {
                config.blinkTimeoutSeconds = t
            }
        }
        return config
    }

    func save() {
        Paths.ensureSupportDir()
        let json: [String: Any] = [
            "herdrAppBinary": herdrAppBinary,
            "hcBinary": hcBinary,
            "appBundleId": appBundleId,
            "blinkTimeoutSeconds": blinkTimeoutSeconds,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: json,
                                                     options: [.prettyPrinted, .sortedKeys])
        else { return }
        try? data.write(to: URL(fileURLWithPath: Paths.configFile))
        Config.current = self
    }
}
