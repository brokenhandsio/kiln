# Theming

Kiln ships with a modern default theme that supports light and dark colour
schemes out of the box. You can customise it in two ways.

## Tweak the palette

The quickest customisation is the palette and fonts:

```swift
theme: .default(
    palette: Palette(primary: .indigo, accent: .teal, defaultMode: .dark),
    fonts: Fonts(text: "Inter", code: "JetBrains Mono")
)
```

## Bring your own templates

For full control, point Kiln at a directory of your own Leaf templates and
assets:

```swift
theme: .custom(directory: "Theme")
```

Templates resolve from your directory first and fall back to the bundled theme,
so you only override what you need:

| File                      | Purpose                       |
| ------------------------- | ----------------------------- |
| `templates/base.leaf`     | The overall page shell        |
| `templates/page.leaf`     | A standard documentation page |
| `templates/home.leaf`     | The home page                 |
| `templates/404.leaf`      | The error page                |
| `css/theme.css`           | Styles                        |

!!! tip "Partials"
    The default theme is split into small partials (`partials/header.leaf`,
    `partials/nav-tree.leaf`, …) so you can override just the navigation, just
    the footer, and so on.

!!! seealso
    See the [Configuration](configuration.md) guide for the full list of theme
    options.
