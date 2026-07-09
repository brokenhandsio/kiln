/// Builds the per-package version switcher for a DocC page — a shared
/// ``DocCSelect`` listing the package's versions, with the current one flagged.
///
/// Switching version keeps the current module and symbol path and swaps the
/// version segment. When a symbol doesn't exist in the target version (its
/// archive has no page at that path), the option falls back to that version's
/// module landing — mirroring Kiln's markdown version switcher.
///
/// Only meaningful when a package declares more than one version; ``renderHTML``
/// returns "" for single-version packages.
struct DocCVersionSwitcher: Sendable {
    let package: APIPackage
    let moduleName: String
    let basePath: String
    /// The set of archive paths present in each version (by version id), so the
    /// switcher can fall back to the module landing when a symbol is absent.
    let pathsByVersion: [String: Set<String>]

    /// Version options for a page at `currentPath` in `currentVersion`.
    func options(currentVersion: PackageVersion, currentPath: String) -> [DocCSelect.Option] {
        package.versions.map { version in
            let urls = DocCURLs(moduleName: moduleName, version: version, basePath: basePath)
            let hasPage = pathsByVersion[version.id]?.contains(currentPath) ?? false
            return DocCSelect.Option(
                label: version.name,
                url: hasPage ? urls.url(forDocCPath: currentPath) : urls.moduleRootURL,
                isCurrent: version.id == currentVersion.id,
                badge: version.badge
            )
        }
    }

    /// The switcher HTML, or "" for a single-version package.
    func renderHTML(currentVersion: PackageVersion, currentPath: String) -> String {
        guard package.versions.count > 1 else { return "" }
        let section = DocCSelect.Section(title: nil, options: options(currentVersion: currentVersion, currentPath: currentPath))
        return DocCSelect.render(label: currentVersion.name, sections: [section], sizeClass: "docc-select--version", accessibleLabel: "Select version")
    }
}
