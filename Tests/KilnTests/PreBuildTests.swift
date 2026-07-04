import Testing
import Foundation
@testable import KilnCLI

@Suite("Asset pre-build hook")
struct PreBuildTests {
    @Test("Flag override wins over configured command")
    func overrideWins() {
        #expect(resolvePreBuildCommand(configured: "npm run build", override: "make assets", disabled: false) == "make assets")
    }

    @Test("--no-pre-build disables the step entirely")
    func disableWins() {
        #expect(resolvePreBuildCommand(configured: "npm run build", override: "make assets", disabled: true) == nil)
    }

    @Test("Configured command is used when no flags are given")
    func configuredUsed() {
        #expect(resolvePreBuildCommand(configured: "npm run build", override: nil, disabled: false) == "npm run build")
    }

    @Test("No command anywhere yields nil")
    func noneYieldsNil() {
        #expect(resolvePreBuildCommand(configured: nil, override: nil, disabled: false) == nil)
        #expect(resolvePreBuildCommand(configured: nil, override: "", disabled: false) == nil)
    }

    @Test("kiln.json parses preBuild command and watch dirs")
    func parsesConfig() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("kiln-cfg-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let json = #"{ "preBuild": { "command": "npm run build", "watch": ["src/scss", "src/js"] } }"#
        try json.write(to: dir.appendingPathComponent("kiln.json"), atomically: true, encoding: .utf8)

        let config = try KilnCLIConfig.load(in: dir)
        #expect(config?.preBuild?.command == "npm run build")
        #expect(config?.preBuild?.watch == ["src/scss", "src/js"])
    }

    @Test("Missing kiln.json yields nil config")
    func missingConfig() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("kiln-cfg-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(try KilnCLIConfig.load(in: dir) == nil)
    }

    @Test("Malformed kiln.json throws")
    func malformedConfig() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("kiln-cfg-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "{ not valid json".write(to: dir.appendingPathComponent("kiln.json"), atomically: true, encoding: .utf8)
        #expect(throws: CLIError.self) { _ = try KilnCLIConfig.load(in: dir) }
    }

    @Test("runCommand captures output")
    func runCommandCaptures() async throws {
        let result = try await ProcessRunner.runCommand("echo kiln-capture-marker")
        #expect(result.exitCode == 0)
        #expect(result.output.contains("kiln-capture-marker"))
    }

    @Test("runCommand throws on a non-zero exit")
    func runCommandThrows() async {
        await #expect(throws: CLIError.self) { try await ProcessRunner.runCommand("exit 3") }
    }
}
