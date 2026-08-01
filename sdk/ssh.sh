#!/usr/bin/env bash

##
# ak.ssh.* — SSH config introspection: enumerate connectable hosts and describe
# them (user@hostname) for menus and shell completion.
#
# Effective values (user, hostname) come from `ssh -G` — the only source that
# honors Include, `Host *` defaults and option inheritance. The config is
# parsed manually ONLY to enumerate Host aliases: `ssh -G` cannot list them.
#
# @env AK_SSH_CONFIG override the config path (default ~/.ssh/config) — mainly
#      for tests; when set, the ak.ssh.hosts.described cache is bypassed.
##

# Include recursion cap — cycle protection (ssh_config Include may nest).
declare -r AK_SSH_INCLUDE_MAX_DEPTH=16

# Print files matching the glob pattern in $1, one per line; nothing when no
# match (nullglob semantics). Works in both bash and zsh: glob expansion of a
# pattern held in a VARIABLE has no portable syntax, so each shell gets its own
# branch (the other shell never executes it, only parses it).
#
# NB (whole file): every `local` carries an explicit initializer. Zsh without
# TYPESET_SILENT PRINTS `name=value` for a bare `local name` whose parameter
# already exists in an enclosing scope — that noise would land in stdout and
# corrupt these functions' machine-readable output.
function __ak.ssh.globFiles() {
  local -r pattern="$1"

  if [[ -n "${ZSH_VERSION:-}" ]]; then
    setopt localoptions nullglob
    local -a matches=()
    matches=( ${~pattern} )
    (( ${#matches[@]} > 0 )) && printf '%s\n' "${matches[@]}"
    return 0
  fi

  compgen -G "${pattern}" 2> /dev/null
  return 0
}

# Recursively print the config file $1 and every file it Includes (depth $2).
# Only existing readable files are printed; a missing file is silent (normal
# case), an unreadable existing one leaves a WARN trace.
function __ak.ssh.configFiles.walk() {
  local -r file="$1"
  local -r -i depth="$2"

  if (( depth > AK_SSH_INCLUDE_MAX_DEPTH )); then
    ak.sh.warn "ak.ssh: Include depth exceeded ${AK_SSH_INCLUDE_MAX_DEPTH} at '${file}' — possible Include cycle, skipping."
    return 0
  fi
  [[ -e "${file}" ]] || return 0
  if [[ ! -r "${file}" ]]; then
    ak.sh.warn "ak.ssh: config file '${file}' is not readable — skipping."
    return 0
  fi

  printf '%s\n' "${file}"

  local key='' rest='' word='' included=''
  while read -r key rest || [[ -n "${key}" ]]; do
    # ssh_config keywords are case-insensitive; separator is whitespace or '='.
    case "${key}" in
      [Ii][Nn][Cc][Ll][Uu][Dd][Ee] | [Ii][Nn][Cc][Ll][Uu][Dd][Ee]=*) ;;
      *) continue ;;
    esac
    [[ "${key}" == *=* ]] && rest="${key#*=} ${rest}"
    # Strip a standalone '=' separator: "Include = path"
    rest="${rest#"${rest%%[![:space:]]*}"}"
    if [[ "${rest}" == '='* ]]; then
      rest="${rest#=}"
      rest="${rest#"${rest%%[![:space:]]*}"}"
    fi

    # One Include line may carry several patterns — walk them all.
    while [[ -n "${rest}" ]]; do
      word="${rest%%[[:space:]]*}"
      rest="${rest#"${word}"}"
      rest="${rest#"${rest%%[![:space:]]*}"}"
      [[ -z "${word}" ]] && continue

      [[ "${word}" == '~'* ]] && word="${HOME}${word#\~}"
      # ssh resolves relative Include paths against ~/.ssh/
      [[ "${word}" != /* ]] && word="${HOME}/.ssh/${word}"

      while IFS= read -r included; do
        [[ -n "${included}" ]] && __ak.ssh.configFiles.walk "${included}" $(( depth + 1 ))
      done < <(__ak.ssh.globFiles "${word}")
    done
  done < "${file}"
}

# Print the effective config file list: main config + all Included files,
# recursively. Empty output when there is no config at all (normal case).
function __ak.ssh.configFiles() {
  __ak.ssh.configFiles.walk "${AK_SSH_CONFIG:-${HOME}/.ssh/config}" 0
}

# Print every connectable Host alias found in ONE config file (no Include
# handling here — the caller walks files). Drops non-connectable patterns:
# wildcards (*, ?) and negations (!host).
function __ak.ssh.hostsFromFile() {
  local -r file="$1"
  [[ -r "${file}" ]] || return 0

  local key='' rest='' name=''
  while read -r key rest || [[ -n "${key}" ]]; do
    case "${key}" in
      [Hh][Oo][Ss][Tt] | [Hh][Oo][Ss][Tt]=*) ;;
      *) continue ;;
    esac
    [[ "${key}" == *=* ]] && rest="${key#*=} ${rest}"
    rest="${rest#"${rest%%[![:space:]]*}"}"
    if [[ "${rest}" == '='* ]]; then
      rest="${rest#=}"
      rest="${rest#"${rest%%[![:space:]]*}"}"
    fi

    # One Host line may carry several names — take them all.
    while [[ -n "${rest}" ]]; do
      name="${rest%%[[:space:]]*}"
      rest="${rest#"${name}"}"
      rest="${rest#"${rest%%[![:space:]]*}"}"
      [[ -z "${name}" ]] && continue
      case "${name}" in
        *\**|*\?*|\!*) continue ;;
      esac
      printf '%s\n' "${name}"
    done
  done < "${file}"
}

##
# Print connectable SSH hosts, one per line, sorted and deduplicated.
# Sources: ~/.ssh/config (or $AK_SSH_CONFIG) + everything it Includes.
# No config file is a normal case: empty output, return 0.
#
# @output {string} host aliases, one per line
#
# @example
#
#   ak.ssh.hosts
#   > lan-admin
#   > vps-bravo
##
function ak.ssh.hosts() {
  local file=''
  while IFS= read -r file; do
    __ak.ssh.hostsFromFile "${file}"
  done < <(__ak.ssh.configFiles) | sort -u
}

##
# Print `user@hostname` for an SSH host from the EFFECTIVE config (`ssh -G`),
# so Include, `Host *` defaults and inheritance are honored automatically.
# Best-effort: prints nothing when `ssh -G` fails (menus degrade to bare names).
#
# @param {string} *host host alias (or any ssh destination)
# @output {string} user@hostname
#
# @example
#
#   ak.ssh.host.describe lan-admin
#   > deploy@198.51.100.6
##
function ak.ssh.host.describe() {
  local -r host="${1:-}"
  if [[ -z "${host}" ]]; then
    ak.sh.err "Usage: ak.ssh.host.describe <host>"
    return 1
  fi

  local -a cfgOpt=()
  [[ -n "${AK_SSH_CONFIG:-}" ]] && cfgOpt=(-F "${AK_SSH_CONFIG}")

  local out=''
  if ! out="$(ssh -G "${cfgOpt[@]}" -- "${host}" 2> /dev/null)"; then
    # ssh -G needs OpenSSH >= 6.8 (2015) — on failure degrade to no description.
    return 0
  fi

  local key='' value='' user='' hostName=''
  while read -r key value; do
    case "${key}" in
      user)     user="${value}"     ;;
      hostname) hostName="${value}" ;;
    esac
    [[ -n "${user}" && -n "${hostName}" ]] && break
  done <<< "${out}"

  [[ -n "${hostName}" ]] || return 0
  printf '%s@%s\n' "${user}" "${hostName}"
}

# Print `host<TAB>user@hostname` for every connectable host (bare host when the
# description is unavailable). Uncached worker for ak.ssh.hosts.described.
function __ak.ssh.hosts.describeAll() {
  local host='' description=''
  while IFS= read -r host; do
    [[ -n "${host}" ]] || continue
    description="$(ak.ssh.host.describe "${host}")"
    if [[ -n "${description}" ]]; then
      printf '%s\t%s\n' "${host}" "${description}"
    else
      printf '%s\n' "${host}"
    fi
  done < <(ak.ssh.hosts)
}

##
# Print `host<TAB>user@hostname` per line — completion-menu source.
# Forks `ssh -G` per host, so the result is cached in a fixed-name file under
# $TMPDIR, invalidated by mtime of the config AND every Included file.
# With $AK_SSH_CONFIG set the cache is bypassed entirely (test mode).
#
# @output {string} host<TAB>user@hostname, one per line
#
# @example
#
#   ak.ssh.hosts.described
#   > lan-admin	deploy@198.51.100.6
##
function ak.ssh.hosts.described() {
  if [[ -n "${AK_SSH_CONFIG:-}" ]]; then
    __ak.ssh.hosts.describeAll
    return 0
  fi

  local -r cacheFile="${TMPDIR:-/tmp}/ak-ssh-hosts-described.${UID}.cache"

  # Fresh = newer than EVERY config file in the effective list.
  if [[ -f "${cacheFile}" ]]; then
    local stale=0 file=''
    while IFS= read -r file; do
      if [[ "${file}" -nt "${cacheFile}" ]]; then
        stale=1
        break
      fi
    done < <(__ak.ssh.configFiles)
    if (( ! stale )); then
      cat "${cacheFile}"
      return 0
    fi
  fi

  local described=''
  described="$(__ak.ssh.hosts.describeAll)"

  # Fixed name + atomic-ish tmp+mv: the file is overwritten, never grows, and a
  # concurrent reader never sees a half-written cache.
  local -r tmpFile="${cacheFile}.$$"
  if [[ -n "${described}" ]]; then
    printf '%s\n' "${described}" > "${tmpFile}"
  else
    : > "${tmpFile}"
  fi
  mv -f "${tmpFile}" "${cacheFile}"

  [[ -n "${described}" ]] && printf '%s\n' "${described}"
  return 0
}
