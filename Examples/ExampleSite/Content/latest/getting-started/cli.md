---
description: The kiln command-line tool — new, build, and serve.
---
# The `kiln` CLI

Kiln ships a command-line tool that wraps the common workflows. Because a Kiln
site is defined in Swift, `kiln` drives your project's own executable (via
`swift run`) rather than reading a config file. Two conventions follow from that:

- your build writes to `./site`, and
- your content lives in `./Content`.

Stick to those and every command works with no flags. See
[Installation](installation.md) to get the binary.

## `kiln new`

Scaffold a new documentation project. Interactive by default — it prompts for
the site name, URL, default language, and any additional languages (from Kiln's
built-in locale list):

```sh
kiln new my-docs
```

Every prompt has a matching flag, so it's fully scriptable too:

```sh
kiln new my-docs \
  --name "My Docs" \
  --url https://docs.example.com \
  --default-language en \
  --language de --language fr \
  --non-interactive
```

`--language` is repeatable and also accepts comma-separated codes
(`--language de,fr`). Unknown locale codes are rejected with the list of valid
ones.

## `kiln serve`

Build the site and serve it locally, rebuilding automatically when you edit a
file:

```sh
kiln serve                     # build, serve ./site at http://127.0.0.1:8080, watch for changes
kiln serve --port 3000         # change the port
kiln serve --directory public  # serve a different output directory
kiln serve --no-watch          # build + serve once, no rebuild-on-change
kiln serve --no-build          # serve the existing output without building first
```

The watcher polls for changes (skipping `.build`, `.git`, `.swiftpm`,
`node_modules`, and the output directory) and re-runs the build. Reload your
browser to see updates.

!!! note "No injected live-reload"
    `serve` rebuilds on change but doesn't auto-refresh the browser — reload to
    see your changes. This keeps the served output byte-for-byte identical to a
    production build.

## `kiln build`

Build the site by running your project's executable:

```sh
kiln build              # writes the static site (to ./site by convention)
kiln build --release    # build in release configuration
```

## Building assets first (`kiln.json`)

If your site has an asset pipeline — say webpack or Sass compiled with `npm` —
you'll want it to run *before* the site is generated, so the latest CSS/JS is
picked up. Drop an optional `kiln.json` at the project root:

```json
{
  "preBuild": {
    "command": "npm run build",
    "watch": ["src/scss", "src/js"]
  }
}
```

Both `kiln build` and `kiln serve` then run `command` before the Swift build,
streaming its output (so webpack warnings/errors are visible). During `kiln
serve`, the directories in `watch` are watched alongside your project, so editing
a stylesheet re-runs the asset build and regenerates the site. The `watch` paths
are resolved relative to the project root and may point outside it (e.g.
`"../design/src"` for a shared design repo).

This is the one piece of CLI configuration Kiln reads from a file — it's a
*tooling* concern, separate from your Swift-defined site config. With no
`kiln.json`, behaviour is unchanged. You can override or skip the step per-run:

```sh
kiln build --pre-build "make assets"   # override the configured command
kiln serve --no-pre-build              # skip the asset step this run
```

## Reference

| Command            | What it does                                              |
| ------------------ | -------------------------------------------------------- |
| `kiln new [path]`  | Scaffold a new project (interactive or via flags).       |
| `kiln build`       | Run your project's executable to generate the site.      |
| `kiln serve`       | Build, serve locally, and rebuild on change.             |
| `kiln --version`   | Print the CLI version.                                   |
| `kiln --help`      | Show help; `kiln <command> --help` for a command.        |

!!! tip "Optional, not required"
    Everything the CLI does, you can also do with `swift run` plus any static
    file server. `kiln` is there for convenience and a familiar `mkdocs`-style
    workflow.
