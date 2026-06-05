---
description: Scaffolde, baue und betrachte deine erste Kiln-Dokumentationsseite.
---
# Schnellstart

Diese Anleitung bringt dich von Null zu einer live aktualisierten Doku-Seite.

## 1. Ein Projekt scaffolden

Am schnellsten geht es mit der CLI:

```sh
kiln new my-docs
cd my-docs
```

`kiln new` fragt nach Name, URL und Sprachen und schreibt dann ein fertig
baubares SwiftPM-Projekt:

```
my-docs/
├── Package.swift
├── Content/
│   └── index.md
└── Sources/
    └── MyDocs/
        └── main.swift
```

## 2. Die Seite konfigurieren

`Sources/MyDocs/main.swift` ist die einzige Quelle der Wahrheit für deine Seite:

```swift
import Kiln

let site = KilnSite(name: "Meine Doku", url: "https://example.com") {
    Page("Willkommen", "index.md")
    Section("Anleitungen") {
        Page("Konfiguration", "guides/configuration.md")
    }
}

try await Kiln.build(site, contentDirectory: "Content", outputDirectory: "site")
```

## 3. Markdown schreiben

Inhalte sind einfaches Markdown unter `Content/`. Erstelle `Content/index.md`:

```markdown
# Willkommen

Hallo, Welt!
```

## 4. Vorschau anzeigen

```sh
kiln serve
```

Das baut die Seite und liefert sie unter <http://127.0.0.1:8080> aus — mit
automatischem Neubau bei jeder Änderung. Lade den Browser neu, um Änderungen zu
sehen.

!!! success "Fertig!"
    Wenn du bereit zum Veröffentlichen bist, führe `kiln build` aus und stelle
    das Verzeichnis `site/` auf einem beliebigen statischen Host bereit.
