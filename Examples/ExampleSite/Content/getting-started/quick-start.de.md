# Schnellstart

Diese Anleitung führt dich durch den Bau deiner ersten Seite.

## 1. Konfiguration erstellen

```swift
import Kiln

let site = KilnSite(name: "Meine Doku", url: "https://example.com") {
    Page("Willkommen", "index.md")
}
```

## 2. Markdown schreiben

Erstelle `Content/index.md`:

```markdown
# Willkommen

Hallo, Welt!
```

## 3. Bauen

```swift
try await Kiln.build(site, contentDirectory: "Content", outputDirectory: "public")
```

!!! success "Fertig!"
    Deine Seite liegt nun in `public/`. Liefere sie mit einem beliebigen
    statischen Webserver aus.
