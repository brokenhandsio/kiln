import ArgumentParser
import Foundation

struct New: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "new",
        abstract: "Scaffold a new Kiln documentation project.",
        discussion: """
        Any value not supplied as an option is prompted for interactively. Pass \
        --non-interactive to skip prompts and use the supplied options (and \
        defaults for the rest), e.g.:

          kiln new my-docs --name "My Docs" --url https://docs.example.com \\
            --default-language en --language de --language fr --non-interactive
        """
    )

    @Argument(help: "Directory for the new project (created if it doesn't exist).")
    var path: String?

    @Option(name: .long, help: "The site's display name.")
    var name: String?

    @Option(name: .long, help: "The Swift target/module name (defaults to a name derived from the directory).")
    var target: String?

    @Option(name: .long, help: "The canonical site URL.")
    var url: String?

    @Option(name: .customLong("default-language"), help: "Default language locale code (e.g. en, de, pt-BR).")
    var defaultLanguage: String?

    @Option(name: .customLong("language"), parsing: .upToNextOption,
            help: "Additional language locale code(s); repeatable or comma-separated.")
    var languages: [String] = []

    @Flag(name: [.customLong("non-interactive"), .customShort("y")],
          help: "Don't prompt; use the supplied options and defaults for anything unspecified.")
    var nonInteractive = false

    func run() throws {
        let fileManager = FileManager.default
        let interactive = !nonInteractive

        // Where to create the project.
        let directoryPath = resolve(path, prompt: "Project directory", default: "docs", interactive: interactive)
        let projectURL = URL(fileURLWithPath: directoryPath,
                             relativeTo: URL(fileURLWithPath: fileManager.currentDirectoryPath))
        let folderName = projectURL.lastPathComponent

        if fileManager.fileExists(atPath: projectURL.appendingPathComponent("Package.swift").path) {
            throw CLIError(message: "A Package.swift already exists in \(directoryPath). Aborting.")
        }

        // Gather inputs (option → prompt → default).
        let targetName = sanitizeTargetName(
            resolve(target, prompt: "Target name", default: defaultTargetName(from: folderName), interactive: interactive)
        )
        let siteName = resolve(name, prompt: "Site name", default: folderName, interactive: interactive)
        let siteURL = resolve(url, prompt: "Site URL", default: "https://example.com", interactive: interactive)

        let defaultLanguageOption = try resolveDefaultLanguage(interactive: interactive)
        let otherLanguages = try resolveAdditionalLanguages(excluding: defaultLanguageOption, interactive: interactive)

        let input = ScaffoldInput(
            targetName: targetName,
            siteName: siteName,
            url: siteURL,
            defaultLanguage: defaultLanguageOption,
            otherLanguages: otherLanguages
        )

        // Write the project.
        let sourcesDir = projectURL.appendingPathComponent("Sources/\(targetName)")
        let contentDir = projectURL.appendingPathComponent("Content")
        try fileManager.createDirectory(at: sourcesDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: contentDir, withIntermediateDirectories: true)

        try write(Scaffold.packageSwift(input: input), to: projectURL.appendingPathComponent("Package.swift"))
        try write(Scaffold.mainSwift(input: input), to: sourcesDir.appendingPathComponent("main.swift"))
        try write(Scaffold.indexMarkdown(input: input), to: contentDir.appendingPathComponent("index.md"))
        for language in otherLanguages {
            try write(Scaffold.localisedIndexMarkdown(input: input, language: language),
                      to: contentDir.appendingPathComponent("index.\(language.localeCode).md"))
        }
        try write(Scaffold.gitignore(), to: projectURL.appendingPathComponent(".gitignore"))
        try write(Scaffold.readme(input: input), to: projectURL.appendingPathComponent("README.md"))

        print("""

        ✅ Created \(siteName) in \(directoryPath)/

        Next steps:
          cd \(directoryPath)
          kiln serve

        """)
    }

    // MARK: - Input resolution

    /// Use the supplied option, otherwise prompt (when interactive), otherwise the default.
    private func resolve(_ provided: String?, prompt label: String, default fallback: String, interactive: Bool) -> String {
        if let provided, !provided.isEmpty { return provided }
        return interactive ? promptForLine(label, default: fallback) : fallback
    }

    private func resolveDefaultLanguage(interactive: Bool) throws -> LanguageOption {
        if let code = defaultLanguage {
            return try languageOption(forCode: code)
        }
        guard interactive else { return builtInLanguageOptions[0] }
        printLanguageList()
        return pickLanguageByNumber(promptForLine("Default language number", default: "1")) ?? builtInLanguageOptions[0]
    }

    private func resolveAdditionalLanguages(excluding defaultLanguageOption: LanguageOption, interactive: Bool) throws -> [LanguageOption] {
        var seen = Set([defaultLanguageOption.localeCode.lowercased()])
        var result: [LanguageOption] = []

        if !languages.isEmpty {
            // Allow both repeated --language flags and comma-separated values.
            for code in languages.flatMap({ $0.split(separator: ",").map(String.init) }) {
                let option = try languageOption(forCode: code)
                if seen.insert(option.localeCode.lowercased()).inserted {
                    result.append(option)
                }
            }
            return result
        }

        guard interactive else { return [] }
        printLanguageList()
        let input = promptForLine("Additional language numbers (comma-separated, blank for none)", default: "")
        for piece in input.split(separator: ",") {
            guard let option = pickLanguageByNumber(String(piece)) else { continue }
            if seen.insert(option.localeCode.lowercased()).inserted {
                result.append(option)
            }
        }
        return result
    }

    // MARK: - Helpers

    private func write(_ contents: String, to url: URL) throws {
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Resolve a locale code (case-insensitive) to a built-in language, or throw.
    private func languageOption(forCode code: String) throws -> LanguageOption {
        let normalized = code.trimmingCharacters(in: .whitespaces).lowercased()
        if let match = builtInLanguageOptions.first(where: { $0.localeCode.lowercased() == normalized }) {
            return match
        }
        let known = builtInLanguageOptions.map(\.localeCode).joined(separator: ", ")
        throw CLIError(message: "Unknown language code '\(code)'. Known codes: \(known).")
    }

    private func pickLanguageByNumber(_ input: String) -> LanguageOption? {
        guard let number = Int(input.trimmingCharacters(in: .whitespaces)),
              number >= 1, number <= builtInLanguageOptions.count else {
            return nil
        }
        return builtInLanguageOptions[number - 1]
    }

    private func printLanguageList() {
        print("\nAvailable languages:")
        for (index, option) in builtInLanguageOptions.enumerated() {
            print(String(format: "  %2d. %@ (%@)", index + 1, option.displayName, option.localeCode))
        }
    }
}

/// Read a line from stdin, returning `fallback` if the input is empty or EOF.
private func promptForLine(_ message: String, default fallback: String) -> String {
    if fallback.isEmpty {
        print("\(message): ", terminator: "")
    } else {
        print("\(message) [\(fallback)]: ", terminator: "")
    }
    guard let line = readLine(), !line.trimmingCharacters(in: .whitespaces).isEmpty else {
        return fallback
    }
    return line.trimmingCharacters(in: .whitespaces)
}

private func defaultTargetName(from folderName: String) -> String {
    let sanitized = sanitizeTargetName(folderName)
    return sanitized.isEmpty ? "Docs" : sanitized
}

/// Turn an arbitrary folder name into a valid Swift target/module name.
private func sanitizeTargetName(_ raw: String) -> String {
    var result = ""
    var capitalizeNext = false
    for character in raw {
        if character.isLetter || character.isNumber {
            result.append(capitalizeNext ? Character(character.uppercased()) : character)
            capitalizeNext = false
        } else {
            capitalizeNext = true
        }
    }
    // A module name can't start with a digit.
    if let first = result.first, first.isNumber {
        result = "Docs" + result
    }
    return result.isEmpty ? "Docs" : result
}
