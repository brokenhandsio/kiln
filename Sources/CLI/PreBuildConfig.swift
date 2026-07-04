import Foundation

/// Optional CLI-level configuration loaded from `kiln.json` at the project root.
///
/// This is *tooling* configuration for the `kiln` CLI — e.g. an asset build step
/// to run before generating the site — and is deliberately separate from the
/// site's Swift-defined content configuration (`KilnSite`). It is entirely
/// optional: with no `kiln.json` present, `kiln build`/`serve` behave exactly as
/// they did before.
struct KilnCLIConfig: Codable, Sendable {
    /// An asset build step run before each Swift build.
    struct PreBuild: Codable, Sendable {
        /// Shell command to run (e.g. `"npm run build"`).
        var command: String
        /// Extra directories to watch during `kiln serve`, in addition to the
        /// project tree. Useful when the asset sources live outside the project
        /// (e.g. a shared design repo: `"../design/src"`). Relative paths are
        /// resolved against the project root.
        var watch: [String]?
    }

    var preBuild: PreBuild?

    /// Load `kiln.json` from `directory`. Returns `nil` if the file is absent;
    /// throws ``CLIError`` if it exists but cannot be parsed.
    static func load(in directory: URL) throws -> KilnCLIConfig? {
        let url = directory.appendingPathComponent("kiln.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(KilnCLIConfig.self, from: data)
        } catch {
            throw CLIError(message: "Failed to parse \(url.path): \(error)")
        }
    }
}

/// Resolve the effective asset pre-build command from the configured value and
/// the CLI flags.
///
/// - `disabled` (`--no-pre-build`) wins and skips the step entirely.
/// - a non-empty `override` (`--pre-build <cmd>`) replaces the configured command.
/// - otherwise the configured command (if any) is used.
func resolvePreBuildCommand(configured: String?, override: String?, disabled: Bool) -> String? {
    if disabled { return nil }
    if let override, !override.isEmpty { return override }
    return configured
}
