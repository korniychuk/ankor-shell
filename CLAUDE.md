# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Summary

AnKor Shell is a modular Bash/Zsh utility library providing helper functions for shell scripting. It is sourced into the user's shell environment (not compiled/built). All public functions follow the `ak.<domain>.<function>()` naming convention. Private/internal functions use `__ak.<domain>.<function>()`.

## Loading & Usage

The library is loaded by sourcing `index.sh` from `~/.bashrc` or `~/.zshrc`. It sequentially sources all modules from `lib/`, then conditionally loads `lib/macos.sh` on macOS. Additional entry points (`cals.sh`, `disk-aliases.sh`, `node-loader.sh`) are sourced separately by the user.

There is no build step, no package manager, no test framework, and no linter configured.

## Architecture

### Module Structure

`index.sh` → sources `config.sh` + all `lib/*.sh` modules in order:

| Module | Domain prefix | Purpose |
|--------|--------------|---------|
| `lib/str.sh` | `ak.str.*` | String manipulation (uses Perl for regex) |
| `lib/array.sh` | `ak.array.*` | Array utilities (`inArray`, `joinBy`) |
| `lib/bash.sh` | `ak.bash.*` | Bash version checking |
| `lib/shell.sh` | `ak.sh.*` | Core shell utilities, colors, user interaction, parameter validation |
| `lib/rnd.sh` | `ak.rnd.*` | Random generation (ObjectID, integers, time) |
| `lib/doc.sh` | — | Documentation utilities |
| `lib/os.sh` | `ak.os.type.*` | OS detection (macOS, Linux, BSD, Windows, Solaris) |
| `lib/dt.sh` | `ak.dt.*` | Date/time (wraps GNU/BSD `date`) |
| `lib/git.sh` | `ak.git.*` | Git operations (largest module, 400+ lines) |
| `lib/inet.sh` | `ak.inet.*` | Network utilities, IP detection, URI encoding |
| `lib/updater.sh` | `ak.updater.*` | Self-update via git pull + cron |
| `lib/docker.sh` | `ak.docker.*` | Docker registry tags, network ops |
| `lib/downloader.sh` | `ak.downloader.*` | M3U8/HLS stream downloader (ffmpeg) |
| `lib/macos.sh` | (conditional) | macOS-specific functions, loaded only on macOS |

### CaLS (Custom and Local Scripts)

`cals.sh` auto-discovers scripts in `custom-scripts/` and `local-scripts/`, creates executable wrappers in `.bin/`, and adds `.bin/` to PATH:
- `custom-scripts/*.sh` → prefixed `aks.<name>` (personal/private utilities)
- `local-scripts/*.sh` → prefixed `akl.<name>` (development utilities)

### Key Variables

- `AK_SCRIPT_PATH` — root directory of the library (set in `index.sh`)
- `AK_CALS_CUSTOM_SCRIPTS_PATH`, `AK_CALS_LOCAL_SCRIPTS_PATH` — script directories
- Color constants in `lib/shell.sh`: `Red`, `Green`, `Yellow`, `Blue`, `Magenta`, `Cyan`, `Gray`, `NC` (No Color)

## Coding Conventions

- Use `declare -r` / `local -r` for readonly variables
- All function-local variables must be declared with `local`
- Parameter validation via `ak.sh.param.required()`
- Error messages go to stderr (`>&2`), fatal errors use `ak.sh.die()`
- Return codes: 0 = success, 1+ = error
- Shell compatibility: detect Bash vs Zsh at runtime, handle GNU vs BSD tool differences
- Perl is used for advanced regex in `ak.str.replace()` and URI encoding
- JSDoc-style comments for function documentation (`@param`, `@output`, `@example`)
- Comments in English only

## Platform Handling

Functions detect and adapt to:
- **Shell type**: `ak.sh.isZsh()` / `ak.sh.isBash()` for conditional behavior
- **OS type**: `ak.os.type.*` functions for platform-specific logic
- **Tool variants**: GNU vs BSD `date`, `gls` vs `ls`, `gdu` vs `du`, `nvim` vs `vim`

## config.sh

Defines shell aliases and adds `$HOME/.local/bin` to PATH. Supports per-project initialization via `.ak-init.sh` in the current directory (sourced automatically if present and not already loaded).
