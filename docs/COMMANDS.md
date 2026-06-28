# WSLMole Command Reference

Complete per-command reference for **WSLMole v2.0.0**. This is the deep reference
linked from the [README](../README.md); for a quick tour see the README's
*Commands* section, and for the man page see `man wslmole` (or
[`docs/wslmole.1`](wslmole.1)).

Every command, flag, sub-action, default, and behavior documented here reflects
the v2.0.0 source (`wslmole` entry script and `lib/*.sh`).

---

## Contents

- [Invocation and global flags](#invocation-and-global-flags)
- [Configuration file](#configuration-file)
- [Safety model](#safety-model)
- [JSON output](#json-output)
- Commands:
  [`clean`](#clean) ·
  [`disk`](#disk) ·
  [`dev`](#dev) ·
  [`diagnose`](#diagnose) ·
  [`packages`](#packages) ·
  [`wsl`](#wsl) ·
  [`scan`](#scan) ·
  [`plan`](#plan) ·
  [`fix`](#fix) ·
  [`update`](#update) ·
  [`help`](#help)

---

## Invocation and global flags

```
wslmole [global options] [command] [command options]
```

Global flags are **only recognized before the first non-flag token** (the
command). Once a command is identified, every remaining argument is forwarded
verbatim to that command's own parser. Unknown `-*` flags seen *before* the
command are also forwarded to the subcommand.

With **no command and no global action flag, WSLMole runs the quick scan** by
default (equivalent to `wslmole scan`).

| Flag | Effect |
|------|--------|
| `-h`, `--help` | Print the full usage screen (`show_usage`) and exit 0. |
| `--version` | Print `WSLMole v<version>` and exit 0. |
| `-i`, `--interactive` | Launch the inline interactive menu and exit 0. |
| `-q`, `--quick` | Run the quick system scan and exit 0. |
| `-v`, `--verbose` | Set `VERBOSE=true` (enables session logging to `~/.local/share/wslmole/wslmole.log`). |
| `--no-color` | Set `NO_COLOR=1` and re-initialize colors (disables colored output). |
| `--format FORMAT` | Set output format. Valid values: `text` (default) or `json`. An invalid value errors and exits 1. Requires an argument. |
| `--format=FORMAT` | Same as `--format`, using `=` syntax. |
| `--yes`, `-y` | Set `FORCE=true` **and** `DRY_RUN=false`. Skips confirmation prompts. **This is the real "force" switch** for `clean` and `dev`, and it must be placed *before* the command. |

> **Forcing destructive actions.** `clean` and `dev` preview by default
> (`DRY_RUN=true`). To actually delete, place the global `--yes`/`-y` *before*
> the command (`wslmole --yes clean apt`), or set `FORCE=true` in the config
> file. See the [help-vs-code note](#a-note-on--f----force) under `clean`.

---

## Configuration file

WSLMole reads `~/.config/wslmole/config` at startup (`load_config`). The file is
parsed as **strict `KEY=VALUE` lines**; `#` comments and blank lines are skipped.

Only the following keys are valid (`VALID_CONFIG_KEYS`):

| Key | Values | Default | Meaning |
|-----|--------|---------|---------|
| `DRY_RUN` | `true` \| `false` | `true` | When true, deletions are previewed only (`safe_delete` logs `[DRY RUN] Would delete`). |
| `FORCE` | `true` \| `false` | `false` | When true, `confirm()` auto-approves all prompts. |
| `VERBOSE` | `true` \| `false` | `false` | When true, enables session logging to the log file. |
| `WSLMOLE_LOG_LEVEL` | `DEBUG` \| `INFO` \| `WARN` \| `ERROR` | `INFO` | Gates which `log_*` messages are written. |
| `WSLMOLE_UPDATE_INTERVAL` | integer seconds | `86400` (24h) | Frequency of the periodic background update check. |

**Validation:** malformed lines, unknown keys, and values containing `$ ; \` |`
are rejected with a config warning on stderr. Only values matching each key's
allowed pattern are applied.

---

## Safety model

- **Dry-run by default.** `DRY_RUN=true` globally. `clean`, `dev`, and `fix` all
  preview by default; `update` also honors `DRY_RUN` (`[DRY RUN] Would update`).
- **Protected paths (exact match, never deleted):** `/ /bin /boot /dev /etc
  /home /lib /lib64 /media /mnt /opt /proc /root /run /sbin /srv /sys /usr /var
  /usr/bin /usr/lib /usr/lib64 /usr/sbin`.
- **Protected prefixes (nothing inside these trees may be deleted):** `/bin
  /sbin /boot /dev /etc /lib /lib64 /proc /sys /usr /run`. Note that `/var`,
  `/tmp`, and `/home` are deliberately **not** prefixes, because WSLMole
  legitimately deletes children there.
- **`safe_delete`** refuses relative paths, blocks `..` path components and `/`,
  and refuses protected paths. It returns `0` success / `1` blocked / `2`
  not-found / `3` permission-denied.
- **Root requirements.** APT operations and `journalctl` vacuuming require root
  (`require_root_or_skip` skips with a warning otherwise). The `wsl` command
  requires a WSL environment or it errors out.

---

## JSON output

Pass the global `--format json` to emit machine-readable output. JSON is written
to file descriptor 3 (`JSON_STDOUT_FD`) via `json_output`; regular stdout is
redirected to stderr so only JSON reaches the caller's stdout. The periodic
update check and the interactive menu are suppressed in JSON/non-TTY mode.

JSON is supported by a subset of commands/modes; each section below notes its
JSON behavior.

---

## `clean`

System cleanup of temp files, caches, logs, and more across 7 categories.

### Synopsis

```
wslmole clean [category...] [options]
```

### Description

Removes cached packages, rotated logs, stale temp files, browser caches, user
caches, and WSL log files. Categories may be passed positionally
(`wslmole clean apt logs`) or via `-c`/`--category`. Cleanup is **previewed by
default** — see [forcing](#a-note-on--f----force).

### Options

| Option | Argument | Default | Description |
|--------|----------|---------|-------------|
| `-n`, `--dry-run` | — | (already the default) | Enable dry-run (preview only, no deletion); sets `DRY_RUN=true`. |
| `-c`, `--category LIST` | comma-separated list | — | Categories to clean. If omitted, the default category set is used. |
| `-h`, `--help` | — | — | Show `clean` help. |

### Categories (`CLEAN_CATEGORIES`)

| Category | Aliases | Action |
|----------|---------|--------|
| `apt` | — | Runs `apt-get clean` + `apt-get autoclean` (**requires root**, else skipped). |
| `snap` | — | Removes disabled snap revisions (validates snap name `^[a-z0-9][a-z0-9-]*$` and revision `^[0-9]+$`). |
| `logs` | — | Deletes rotated logs in `/var/log` (`*.gz`, `*.old`, `*.1`, `*.2`, `*.3`) via `safe_delete` + `journalctl --vacuum-time=7d` (**root**). |
| `tmp` | `temp` | Deletes files older than 7 days in `/tmp` and `/var/tmp`, plus optional `~/.cache` cleanup of files older than 7 days. |
| `browser` | — | Clears cache dirs for Google Chrome, Chromium, Mozilla Firefox, Microsoft Edge under `~/.cache`. |
| `user` | `userdata` | Thumbnail cache (`~/.cache/thumbnails`), trash (`~/.local/share/Trash`), `recently-used.xbel`. |
| `wsl` | — | Deletes `/var/log/wsl*.log` and prints `/mnt/c` performance tips (no-op if not in WSL). |

Special tokens:

- `all` — expands to all 7 categories.
- `preview` — **dispatcher-only** (used by the interactive menu); forces
  `DRY_RUN` for a full preview of all categories. Not listed in CLI help.

**Default when no category is given** (`CLEAN_DEFAULT_CATEGORIES`): `apt`,
`snap`, `logs`, `tmp`, `wsl`. (`browser` and `user` are opt-in/low-value in
WSL.) An unknown category prints `suggest_correction`.

### A note on `-f` / `--force`

The `clean` help text advertises `-f, --force`, but **`clean`'s own parser has
no `-f`/`--force` case** — passing it *after* `clean` triggers `Unknown option`.
Forcing actually comes from the **global `--yes`/`-y`** flag placed *before* the
command (which sets `FORCE=true` and `DRY_RUN=false`), or from `FORCE=true` in
the config file. Do not rely on `wslmole clean -f`.

### Root requirements

`apt` (apt-get clean/autoclean) and the `journalctl --vacuum-time` step of
`logs` require root; without it they are skipped with a warning.

### Examples

```bash
wslmole clean                       # preview default categories (apt,snap,logs,tmp,wsl)
wslmole clean apt logs              # preview only apt + logs
wslmole clean -c browser,user       # preview browser + user caches
wslmole --yes clean all             # actually clean every category (force)
wslmole --yes clean apt             # actually clean APT cache (run as root)
```

---

## `disk`

Disk usage analysis with 6 view modes.

### Synopsis

```
wslmole disk [path] [options]
```

### Description

Analyzes disk usage at `path` (default `/`) using one of six modes. The path
must exist and be a directory. `disk` is read-only.

### Options

| Option | Argument | Default | Description |
|--------|----------|---------|-------------|
| `-m`, `--mode MODE` | mode name | `summary` | Analysis mode (see below). |
| `-d`, `--depth N` | integer | `3` | Tree depth for `tree` mode. |
| `-n`, `--top N` | integer | `10` | Number of results to show. |
| `-h`, `--help` | — | — | Show `disk` help. |

### Modes (`DISK_MODES`)

The mode can also be given positionally with aliases.

| Mode | Positional aliases | Action |
|------|--------------------|--------|
| `summary` | `usage` | `df` overview + top-level dir sizes (for `/` shows `/home /var /tmp /opt /usr /snap`), or immediate subdir sizes. |
| `tree` | — | `du --max-depth` hierarchical tree sorted by size (`head -40`). |
| `files` | `file`, `large`, `largest` | Largest individual files (`find -printf` size, top N). |
| `folders` | `folder`, `dirs` | Largest immediate subdirectories (`du -sb`, top N). |
| `types` | `type` | Usage grouped by file extension (`awk` aggregation). |
| `old` | — | Files not modified in 90+ days, top N by size. |

### JSON output

JSON is emitted for the `summary`, `files`, and `old` modes.

### Examples

```bash
wslmole disk                        # filesystem summary of /
wslmole disk ~                      # summary of home directory
wslmole disk -m tree -d 2 /var      # 2-level size tree of /var
wslmole disk ~ -m files -n 20       # 20 largest files under home
wslmole disk -m folders /usr        # largest immediate subdirs of /usr
wslmole disk -m types ~/Downloads   # usage grouped by extension
wslmole --format json disk -m old / # JSON list of 90+ day-old files
```

---

## `dev`

Developer artifact cleanup (build dirs, dependency dirs, caches).

### Synopsis

```
wslmole dev [path] [options]
```

### Description

Finds and removes developer build/dependency/cache artifacts under `path`
(default `.`). Uses `find -prune` to locate artifact directories and deletes via
`safe_delete`. The path must exist and be a directory. Cleanup is **previewed by
default**.

### Options

| Option | Argument | Default | Description |
|--------|----------|---------|-------------|
| `-n`, `--dry-run` | — | (already the default) | Enable dry-run (preview only); sets `DRY_RUN=true`. |
| `-t`, `--types LIST` | comma-separated list | — | Artifact types to target. If omitted, the full list is used. |
| `--older-than DAYS` | integer days | — | Only target artifacts whose mtime is older than `DAYS` days. |
| `-h`, `--help` | — | — | Show `dev` help. |

### Artifact types (`DEV_ARTIFACTS`)

`node_modules`, `target`, `__pycache__`, `.gradle`, `venv`, `.venv`, `build`,
`dist`, `.next`, `.nuxt`, `.cache`, `vendor`, `.tox`, `.pytest_cache`,
`coverage`, `.nyc_output`.

- Types may be passed positionally.
- Alias: `node` → `node_modules`.
- `all` — expands to the full artifact list.
- **Default when no type is given:** the full `DEV_ARTIFACTS` list.

### A note on `-f` / `--force`

As with `clean`, the `dev` help text advertises `-f, --force`, but **`dev`'s
parser has no `-f`/`--force` case** (it would hit `Unknown option` after `dev`).
Forcing comes from the global `--yes`/`-y` flag placed *before* the command, or
`FORCE=true` in config.

### JSON output

JSON includes `path`, `count`, `total_bytes`, and `dry_run`.

### Examples

```bash
wslmole dev                         # preview all artifacts under current dir
wslmole dev ~/projects              # preview artifacts under ~/projects
wslmole dev node                    # target node_modules only
wslmole dev -t target,dist          # target Rust target + dist dirs
wslmole dev --older-than 30 ~/code  # only artifacts older than 30 days
wslmole --yes dev all ~/projects    # actually delete all artifacts (force)
```

---

## `diagnose`

System diagnostics for processes, memory, services, and WSL resources.

### Synopsis

```
wslmole diagnose [type] [options]
```

### Description

Reports on running processes, memory usage, systemd services, and WSL resources.
The diagnostic type is given positionally (default `all`). Read-only.

### Options

| Option | Argument | Default | Description |
|--------|----------|---------|-------------|
| `-h`, `--help` | — | — | Show `diagnose` help. |

### Types (`DIAGNOSE_TYPES`)

| Type | Aliases | Action |
|------|---------|--------|
| `process` | `processes` | Top 10 CPU and top 10 memory consumers via `ps aux`. |
| `memory` | `mem` | `/proc/meminfo` breakdown with colored progress bar + swap. |
| `service` | `services` | systemd failed services, running count, top 5 services by `MemoryCurrent` (no-op if systemctl/systemd unavailable). |
| `wsl` | — | WSL version/kernel/distro/hostname, `.wslconfig` contents, `df -h /`. |

- `all` (the default) runs `process`, `memory`, `service`, and — **only if in
  WSL** — `wsl` diagnostics.

### JSON output

JSON output is available for the `memory` diagnostic.

### Examples

```bash
wslmole diagnose                    # run all diagnostics
wslmole diagnose memory             # memory breakdown only
wslmole diagnose services           # failed/running systemd services
wslmole --format json diagnose memory   # machine-readable memory stats
```

---

## `packages`

Package manager wrapper for APT + Snap.

### Synopsis

```
wslmole packages [action] [options]
```

### Description

Audits and maintains both APT and Snap packages. The action is given
positionally (default `audit`).

### Options

| Option | Argument | Default | Description |
|--------|----------|---------|-------------|
| `-h`, `--help` | — | — | Show `packages` help. |

### Actions (`PACKAGES_ACTIONS`)

| Action | Aliases | Action |
|--------|---------|--------|
| `audit` | `check` | Lists upgradable APT packages and `snap refresh --list` updates. |
| `update` | — | `apt-get update && apt-get upgrade -y` (**root**, confirm) + `snap refresh` (confirm). |
| `autoremove` | — | `apt-get --dry-run autoremove` preview, then `apt-get autoremove -y` (**root**, confirm). |
| `clean` | — | Shows APT cache size, runs `apt-get clean` + `autoclean` (**root**, confirm), reports disabled snap revisions. |
| `list` | — | Counts `dpkg --get-selections` and lists `snap list`. |

### Root requirements

`update`, `autoremove`, and `clean` perform APT write operations and require
root (and confirmation).

### JSON output

JSON output is available for `audit` (includes `has_updates`).

### Examples

```bash
wslmole packages                    # audit available updates (default)
wslmole packages list               # count installed APT + list snaps
sudo wslmole packages update        # update APT + Snap packages
sudo wslmole packages autoremove    # remove orphaned APT packages
wslmole --format json packages audit    # machine-readable update check
```

---

## `wsl`

WSL-specific tools and information.

### Synopsis

```
wslmole wsl [action] [options]
```

### Description

Reports WSL environment details and helps configure WSL. The action is given
positionally (default `info`).

> **The entire `wsl` command requires a WSL environment.** If not running in
> WSL, it prints `Not running in WSL` and returns 1.

### Options

| Option | Argument | Default | Description |
|--------|----------|---------|-------------|
| `-h`, `--help` | — | — | Show `wsl` help. |

### Actions (`WSL_ACTIONS`)

| Action | Aliases | Action |
|--------|---------|--------|
| `info` | — | WSL version/kernel/distro/hostname/user/shell, Windows `.wslconfig`, `/etc/wsl.conf`. |
| `memory` | `mem` | Allocated/used/available memory, `.wslconfig` `memory=` limit, swap status. |
| `compact` | `compact-guide` | Step-by-step guide to compacting the WSL2 `ext4.vhdx` (`wsl --shutdown`, `wsl --manage <distro> --compact`, `diskpart` alternative). |
| `interop` | — | `WSLInterop` binfmt_misc status, Windows PATH entries, `/etc/wsl.conf` `[interop]` section; checks `cmd.exe`/`powershell.exe`/`explorer.exe`/`code`. |

### JSON output

JSON output is available for the `info` action.

### Examples

```bash
wslmole wsl                         # WSL environment info (default)
wslmole wsl memory                  # WSL memory + swap status
wslmole wsl compact                 # guide to shrinking the vhdx
wslmole wsl interop                 # Windows interop status
wslmole --format json wsl info      # machine-readable WSL info
```

---

## `scan`

Quick system health scan with score and recommendations.

### Synopsis

```
wslmole scan
```

### Description

Runs `run_quick_scan` (`lib/quickscan.sh`) and reports a health score, grade,
cleanable-space estimate, and recommendations. `scan` has **no sub-actions**.

This is also the **default behavior** when `wslmole` is run with **no command**,
and is reachable via the global `-q`/`--quick` flag.

### Options

| Option | Argument | Default | Description |
|--------|----------|---------|-------------|
| `-h`, `--help` | — | — | Show `scan` usage. |

Any other option prints `Unknown option` and returns 1.

### Scoring

A `health_score` from 0–100 is computed, with a grade:

| Grade | Score |
|-------|-------|
| Excellent | ≥ 90 |
| Good | ≥ 70 |
| Fair | ≥ 50 |
| Poor | otherwise |

**Penalties:**

- Memory usage ≥ 80% → −15; ≥ 60% → −5.
- Disk usage ≥ 90% → −20; ≥ 75% → −10.
- Each failed systemd service → −5.
- No `.wslconfig` in WSL → −5.
- More than 10 upgradable APT packages → −5.

The scan also reports a **cleanable space estimate** (APT cache, old/rotated
logs, disabled snap revisions at ~100MB/rev, `/tmp`) and recommendations.

### JSON output

JSON output is supported and includes `health_score`, `grade`,
`memory_percent`, `disk_percent`, `cleanable{...}`, and `recommendations`.

### Examples

```bash
wslmole                             # quick scan (default with no command)
wslmole scan                        # quick scan
wslmole -q                          # quick scan via global flag
wslmole --format json scan          # machine-readable health report
```

---

## `plan`

Show a risk-labeled action plan without changing the system (read-only).

### Synopsis

```
wslmole plan [options]
```

### Description

Builds an action plan via `plan_collect` from lightweight checks and prints it
with risk labels. **`plan` never modifies the system.** It has no sub-actions.

Risk levels used: `low`, `medium`, `review`. Plan item categories produced:
`apt`, `logs`, `tmp`, `snap`, `disk`, `packages`, `services`, `wslconfig`,
`dev`. Auto-eligible (low-risk) categories are `apt`, `logs`, `tmp`.

**Checks performed:** APT cache size; rotated logs (>0); `/tmp` + `/var/tmp`
files >7d; disabled snap revisions; root filesystem ≥75% full; >10 upgradable
APT packages; failed systemd services; missing `.wslconfig` (WSL); dev artifacts
under `$HOME` (maxdepth 4, first 20: `node_modules`, `target`, `__pycache__`,
`.venv`, `venv`).

### Options

| Option | Argument | Default | Description |
|--------|----------|---------|-------------|
| `--risk RISK` | `low` \| `medium` \| `review` | — | Show only items with the given risk (any other value errors). |
| `--auto` | — | — | Show only low-risk automatic actions. |
| `--category CATEGORY` | category name | — | Show only one category (e.g. `logs`, `tmp`, `snap`, `apt`, `disk`, `packages`, `services`, `wslconfig`, `dev`). |
| `-h`, `--help` | — | — | Show `plan` help. |

### JSON output

JSON output is supported. The output is `items[]`, each with `title`, `risk`,
`detail`, `command`, `auto`, and `category`.

### Examples

```bash
wslmole plan                        # full risk-labeled plan
wslmole plan --risk low             # only low-risk items
wslmole plan --auto                 # only auto-applicable (low-risk) items
wslmole plan --category logs        # only the logs category
wslmole --format json plan          # machine-readable plan
```

---

## `fix`

Preview and apply low-risk automatic cleanup actions from the action plan.

### Synopsis

```
wslmole fix [options]
```

### Description

Runs `plan_collect`, then either prints the plan (text or JSON) or applies the
auto-eligible actions. Only items whose plan `auto` flag is `true` **and** whose
category passes the `--only` filter are applied. `plan_apply_auto_actions` maps
categories `apt`/`logs`/`tmp` → `cmd_clean_category`; any other auto category is
skipped with a notice.

Behavior:

- If no auto actions are available: prints success and exits.
- If `DRY_RUN`: prints a `DRY RUN mode` warning and stops.
- Otherwise: confirms before applying.

**`fix` previews by default** (`DRY_RUN=true`). Pass `--yes`, or answer the
confirm prompt, to actually apply. Unlike `clean`/`dev`, **`fix` parses `--yes`
itself.**

### Options

| Option | Argument | Default | Description |
|--------|----------|---------|-------------|
| `-n`, `--dry-run` | — | (already the default) | Show the plan without applying actions; sets `DRY_RUN=true`. |
| `--only LIST` | comma-separated categories | — | Apply only these automatic categories (help example: `logs,tmp`). Requires an argument. |
| `--yes` | — | — | Apply low-risk actions without prompting; sets `FORCE=true` and `DRY_RUN=false`. |
| `-h`, `--help` | — | — | Show `fix` help. |

### JSON output

In JSON mode, `fix` prints the plan (`plan_print_json`) and **returns without
applying** anything.

### Examples

```bash
wslmole fix                         # preview low-risk auto actions (default)
wslmole fix --dry-run               # explicit preview
wslmole fix --only logs,tmp         # restrict to logs + tmp categories
wslmole fix --yes                   # apply low-risk cleanup without prompting
wslmole --format json fix           # print the plan as JSON (no changes)
```

---

## `update`

Check for and install updates from the Git repository (self-update).

### Synopsis

```
wslmole update [options]
```

### Description

By default performs a self-update (`perform_update`): fetches tags, compares
versions, and optionally checks out the latest tag. **Requires a Git checkout**
(`.git`). Honors `DRY_RUN` (`[DRY RUN] Would update`).

A periodic background auto-check (`maybe_check_for_updates`) also runs at startup
every `WSLMOLE_UPDATE_INTERVAL` seconds (default 86400 / 24h). It is skipped in
JSON mode and non-TTY environments.

### Options

| Option | Argument | Default | Description |
|--------|----------|---------|-------------|
| `-c`, `--check` | — | — | Check for updates without installing (`check_for_updates` only; reports up-to-date / update available). |
| `-h`, `--help` | — | — | Show `update` help. |

### Self-update safety

- `_validate_tag` requires strict semver tags `^v[0-9]+.[0-9]+.[0-9]+$`.
- `_get_latest_tag` picks the highest `v[0-9]*` by `version:refname`.
- Before checkout it verifies that `origin` is the official repo
  (`https://github.com/mrelph/WSLMole.git`, with or without `.git`) and prompts
  if not.
- It runs `git verify-tag` and **warns loudly if the tag is not GPG-signed**
  (the checked-out code is sourced on the next run).
- It stashes local modifications with consent, checks out the tag (detached
  HEAD), and reports how to return to `master`.

### JSON output

JSON output is supported for check results.

### Examples

```bash
wslmole update                      # check and install the latest tagged release
wslmole update --check              # check only, do not install
wslmole --format json update --check    # machine-readable check result
```

---

## `help`

Show general usage or command-specific help.

### Synopsis

```
wslmole help [command]
```

### Description

With no argument, prints the full usage screen (`show_usage`). With a command
argument, dispatches to that command's own help: `clean`, `disk`, `dev`,
`diagnose`, `packages`, `wsl`, `scan`, `plan`, `fix`, `update`.

An unknown command argument prints `suggest_correction` over the valid command
list and exits 1.

Help is also reachable via the global `-h`/`--help`, which prints `show_usage`.

### Examples

```bash
wslmole help                        # full usage screen
wslmole help clean                  # clean-specific help
wslmole -h                          # full usage screen (global flag)
```

---

*WSLMole v2.0.0 — source: `wslmole` entry script and `lib/*.sh`
(`common.sh`, `clean.sh`, `disk.sh`, `dev.sh`, `diagnose.sh`, `packages.sh`,
`wsl.sh`, `quickscan.sh`, `plan.sh`, `update.sh`, `menu.sh`).*
