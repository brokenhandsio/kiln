---
description: Kiln ist ein Generator für Dokumentationsseiten in Swift — typsichere Konfiguration, Lokalisierung, Themes und Suche.
---
# Willkommen bei Kiln

**Kiln** ist ein Generator für Dokumentationsseiten, geschrieben in Swift. Du
definierst deine Seite in einer typsicheren Swift-Konfiguration und Kiln macht
aus einem Verzeichnis voller Markdown eine schnelle, moderne Website.

!!! tip "Neu hier?"
    Schau dir die [Installation](getting-started/installation.md) an, um in
    wenigen Minuten loszulegen.

## Warum Kiln?

- **Komplett Swift** — konfiguriere alles in Swift, kein YAML nötig.
- **Lokalisiert** — erstklassige Mehrsprachigkeit mit Rückfall auf die
  Standardsprache.
- **Anpassbar** — mit einem frischen Standard-Theme, oder bringe deine eigenen
  Leaf-Vorlagen mit.
- **Durchsuchbar** — für jede Sprache wird ein Such-Index erzeugt.

## Ein kurzer Vorgeschmack

```swift
let site = KilnSite(name: "Meine Doku", url: "https://example.com") {
    Page("Willkommen", "index.md")
}

try await Kiln.build(site, contentDirectory: "Content", outputDirectory: "public")
```

!!! warning
    Kiln wird aktiv entwickelt. APIs können sich vor dem 1.0-Release noch ändern.
