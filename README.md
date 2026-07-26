# clean-me-mac (`clmac`)

Focused macOS cleanup CLI. Solves three pains that macOS Storage Settings
doesn't:

1. **What's actually eating my disk?** — categorized scan, not macOS's
   confusing "Documents / System Data" buckets.
2. **Why is app data still here after I uninstalled?** — finds leftover
   Library data with no matching installed app.
3. **What's safe to delete right now?** — curated presets for caches that
   regenerate (`huggingface`, `gradle`, `npm`, `pnpm`, `yarn`, Xcode DerivedData, …).

Pure Bash 5 with a hand-rolled raw-terminal picker UI (no `fzf` dependency),
in the borderless, `▶`/`☐`/`☑` style of [tw93/mole](https://github.com/tw93/mole)
— credit to that project for the interaction design this follows. `clmac
explore`'s bar-chart drill-down optionally builds a small Go+Bubbletea
component for a smoother analyzer; without Go installed it falls back to an
equivalent bash implementation automatically.

---

## Screenshots

### `clmac` — interactive menu

![clmac's interactive menu: a block-letter CLMAC wordmark above a color-coded list of commands](docs/menu.png)

---

## Install

```sh
# Requirements
brew install bash jq       # bash 5 + jq required
brew install go            # optional — builds the enhanced `clmac explore` analyzer

# Clone and install
git clone https://github.com/gusentanan/clean-me-mac.git
cd clean-me-mac
./install.sh               # symlinks to /opt/homebrew/bin/clmac, builds clmac-explore if Go is present
```

## Commands

| Command | What it does |
|---|---|
| `clmac` | Interactive launcher menu (arrow keys, in a terminal) |
| `clmac scan` | Categorized disk usage breakdown |
| `clmac explore` | Interactive disk usage browser — bar-chart drill-down |
| `clmac orphans` | Find & remove leftover app data |
| `clmac clean [preset]` | Run a known-safe cleanup preset |
| `clmac clean --list` | List all presets with current size |
| `clmac clean --all-safe` | Run every "safe" preset (caches that regenerate) |
| `clmac doctor` | One-screen summary |

### Global flags

- `-n` / `--dry-run` — preview without deleting
- `-y` / `--yes` — skip confirmation prompts
- `--trash` — move to Finder Trash (recoverable) instead of `rm -rf`
- `-v` / `--verbose`
- `--json` — machine-readable output (scan, doctor, orphans)

Every successful delete is appended to `~/Library/Logs/clmac/operations.log`
(tab-separated: timestamp, action, bytes, path), so you can audit what was
removed.

## Presets

| Preset | Safe? | What it cleans |
|---|---|---|
| `huggingface` | ✅ | `~/.cache/huggingface` model weights |
| `gradle` | ✅ | `~/.gradle/caches`, daemon |
| `dart-server` | ✅ | `~/.dartServer` |
| `pub-cache` | ✅ | `~/.pub-cache/hosted`, `~/.pub-cache/git` |
| `npm` | ✅ | `~/.npm/_cacache`, `~/.npm/_logs` |
| `pnpm` | ✅ | `~/Library/pnpm/store`, `~/.pnpm-store` |
| `yarn` | ✅ | `~/.yarn/cache`, `~/Library/Caches/Yarn` |
| `node-modules` | ⚠️ | Interactively pick `node_modules` dirs to remove |
| `cocoapods` | ✅ | CocoaPods cache + repos |
| `xcode-derived` | ✅ | Xcode DerivedData |
| `xcode-archives` | ⚠️ | Xcode build archives — do not delete if needed for App Store |
| `xcode-device-support` | ✅ | iOS device symbols (redownloaded on connect) |
| `android-studio` | ✅ | Android Studio caches & logs across all installed versions |
| `vscode-cache` | ✅ | VS Code caches, logs, GPU/code caches |
| `chrome-cache` | ✅ | Chrome cache directories |
| `safari-cache` | ✅ | Safari + WebKit content cache |
| `firefox-cache` | ✅ | Firefox HTTP & startup cache (all profiles) |
| `brew-cleanup` | ✅ | Runs `brew cleanup --prune=all` |
| `trash` | ⚠️ | Empties `~/.Trash` permanently |

## Orphan detection

Walks these locations and matches each entry against installed app bundle IDs
(read from `Info.plist` of every `.app` in `/Applications`,
`~/Applications`, `/System/Applications`):

- `~/Library/Application Support`
- `~/Library/Caches`
- `~/Library/Containers` (via container metadata plist)
- `~/Library/Preferences`
- `~/Library/Logs`
- `~/Library/Saved Application State`
- `~/Library/HTTPStorages`

Filters out Apple-managed bundle IDs (`com.apple.*`). For folders with
non-bundle-ID names (e.g., `CrossOver`, `Whisky`), uses a built-in mapping
plus a user-extensible list at `~/.config/clmac/known-apps.txt`.

**Format** for `known-apps.txt` (tab-separated):

```
FolderName	com.example.bundleid
```

## Examples

```sh
# Arrow-key launcher — no subcommand to remember
clmac

# What's eating my disk?
clmac scan

# Browse it interactively instead — bar-chart drill-down
clmac explore

# Find orphans, preview only
clmac orphans --dry-run

# Free up the huggingface cache without confirmation
clmac clean huggingface -y

# Wipe everything safe to wipe
clmac clean --all-safe

# One-screen summary
clmac doctor
```

## Layout

```
clean-me-mac/
├── clmac                   entrypoint
├── install.sh              symlinks into /opt/homebrew/bin, builds cmd/explore if Go is present
├── Makefile                `make build` — builds bin/clmac-explore
├── go.mod                  Go module for cmd/explore (optional component)
├── cmd/
│   └── explore/            Go+Bubbletea bar-chart disk analyzer (clmac explore's enhanced path)
├── lib/
│   ├── common.sh           colors, icons, size helpers, confirm, safe_rm
│   ├── tui.sh               raw-terminal picker engine (▶ pointer, ☐/☑ checkboxes, no fzf)
│   ├── ui.sh               select_multi/select_menu — dispatches to tui.sh or a numbered fallback
│   ├── apps.sh             bundle ID resolution
│   ├── menu.sh             cmd_menu — top-level interactive launcher
│   ├── scan.sh             cmd_scan
│   ├── explore.sh          cmd_explore — execs the Go analyzer, or a bash bar-chart fallback
│   ├── orphans.sh          cmd_orphans
│   ├── clean.sh            cmd_clean + preset loader
│   └── doctor.sh           cmd_doctor
└── presets/                one file per preset
```
