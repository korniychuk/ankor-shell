# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Summary

AnKor Shell is a modular Bash/Zsh utility library providing helper functions for shell scripting. It is sourced into the user's shell environment (not compiled/built). All public functions follow the `ak.<domain>.<function>()` naming convention. Private/internal functions use `__ak.<domain>.<function>()`.

## Loading & Usage

The library is loaded by sourcing `index.sh` from `~/.bashrc` or `~/.zshrc`. It sequentially sources all modules from `sdk/`, then conditionally loads `sdk/macos.sh` on macOS. Additional entry points (`cals.sh`, `disk-aliases.sh`, `node-loader.sh`) are sourced separately by the user.

There is no build step, no package manager, no test framework, and no linter configured.

## Architecture

### Module Structure

`index.sh` → sources `config.sh` + all `sdk/*.sh` modules in order:

| Module | Domain prefix | Purpose |
|--------|--------------|---------|
| `sdk/str.sh` | `ak.str.*` | String manipulation (uses Perl for regex) |
| `sdk/array.sh` | `ak.array.*` | Array utilities (`inArray`, `joinBy`) |
| `sdk/bash.sh` | `ak.bash.*` | Bash version checking |
| `sdk/shell.sh` | `ak.sh.*` | Core shell utilities, colors, user interaction, parameter validation |
| `sdk/rnd.sh` | `ak.rnd.*` | Random generation (ObjectID, integers, time) |
| `sdk/doc.sh` | — | Documentation utilities |
| `sdk/os.sh` | `ak.os.type.*` | OS detection (macOS, Linux, BSD, Windows, Solaris) |
| `sdk/dt.sh` | `ak.dt.*` | Date/time (wraps GNU/BSD `date`) |
| `sdk/git.sh` | `ak.git.*` | Git operations (largest module, 400+ lines) |
| `sdk/inet.sh` | `ak.inet.*` | Network utilities, IP detection, URI encoding |
| `sdk/updater.sh` | `ak.updater.*` | Self-update via git pull + cron |
| `sdk/docker.sh` | `ak.docker.*` | Docker registry tags, network ops |
| `sdk/downloader.sh` | `ak.downloader.*` | M3U8/HLS stream downloader (ffmpeg) |
| `sdk/macos.sh` | (conditional) | macOS-specific functions, loaded only on macOS |

### CaLS (Custom and Local Scripts)

`cals.sh` auto-discovers scripts in `custom-scripts/` and `local-scripts/`, creates executable wrappers in `.bin/`, and adds `.bin/` to PATH:
- `custom-scripts/*.sh` → prefixed `aks.<name>` (personal/private utilities)
- `local-scripts/*.sh` → prefixed `akl.<name>` (development utilities)

### Key Variables

- `AK_SCRIPT_PATH` — root directory of the library (set in `index.sh`)
- `AK_CALS_CUSTOM_SCRIPTS_PATH`, `AK_CALS_LOCAL_SCRIPTS_PATH` — script directories
- Color constants in `sdk/shell.sh`: `Red`, `Green`, `Yellow`, `Blue`, `Magenta`, `Cyan`, `Gray`, `NC` (No Color)

## Privacy — this repository is PUBLIC

Never commit real infrastructure identifiers, in code examples, doc-comments or task docs
alike: host aliases, internal or public IP addresses, private DNS suffixes, mesh/VPN
subnets, or the SSH usernames paired with them. Together they are a map of the operator's
fleet, and the whole history is world-readable.

Use placeholders instead — `vps-alpha`/`lan-admin` for hosts, `*.example.internal` for a
private suffix, and the RFC 5737 documentation ranges for addresses (`198.51.100.0/24`,
`203.0.113.0/24`, `192.0.2.0/24`). Real values belong in the private infrastructure repo.

Before committing, grep the staged diff for the fleet's real names and for digits shaped
like an address. This rule was written after a history rewrite removed exactly such data.

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
