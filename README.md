# nfsctl

Modular, idempotent NFS configuration tool for Debian.

## Overview

`nfsctl` is a CLI tool composed of modular Bash scripts for configuring NFS servers and clients on Debian. It manages package installation, `/etc/exports`, systemd services, and firewall rules (ufw and nftables).

Key properties:

- **Idempotent** -- every command is safe to run repeatedly. It checks current state, skips work already done, and verifies the result.
- **Dual-mode** -- each command works interactively (prompt-driven wizard) or non-interactively (CLI flags + `--yes`), making the tool usable by both humans and automation.
- **Non-destructive** -- only touches `/etc/exports` lines tagged `# Managed by nfsctl`. Hand-configured exports are never modified. Backups are created before every change.
- **Dry-run capable** -- `--dry-run` shows exactly what would happen without making any changes.

## Requirements

- Debian or derivative (Ubuntu, etc.)
- Bash 4.4+
- Root access (via `sudo`) for most commands
- `export list` and `status` work without root (with reduced information)

## Quick Start

```bash
git clone <repo-url> nfs-on-debian
cd nfs-on-debian

# Full guided setup (interactive)
sudo ./nfsctl setup

# Verify
sudo ./nfsctl status
```

Or fully non-interactive:

```bash
sudo ./nfsctl setup --yes \
  --path /srv/nfs/data \
  --client "192.168.1.0/24" \
  --options "rw,sync,no_subtree_check"
```

## Installation

`nfsctl` runs directly from its source directory. No build step is required.

```bash
git clone <repo-url> /opt/nfsctl
ln -s /opt/nfsctl/nfsctl /usr/local/bin/nfsctl
```

To override default configuration values, create `/etc/nfsctl/defaults.conf` with any variables from `conf/defaults.conf` that you want to change. System overrides take precedence over bundled defaults.

## Usage

### Global Flags

| Flag | Description |
|------|-------------|
| `-v`, `--verbose` | Enable debug-level log output |
| `-n`, `--dry-run` | Show what would be done without making changes |
| `-y`, `--yes` | Auto-confirm all prompts (non-interactive mode) |
| `-h`, `--help` | Show help and exit |

Global flags must appear before the command:

```bash
sudo nfsctl --dry-run --verbose export add --path /srv/data --client "10.0.0.0/8"
```

### Commands

#### `setup` -- Full Guided Setup

Walks through the complete NFS server setup in five steps:

1. **Package installation** -- installs `nfs-kernel-server` and `nfs-common` (or `nfs-common` only for client mode)
2. **Export configuration** -- add one or more exports (interactive loop or single export via flags)
3. **Apply exports** -- runs `exportfs -ra`
4. **Firewall** -- detects ufw/nftables and opens NFS ports (2049, 111, 20048)
5. **Start service** -- enables and starts `nfs-kernel-server`

```bash
# Interactive wizard
sudo nfsctl setup

# Non-interactive with explicit values
sudo nfsctl setup --yes --path /srv/nfs --client "192.168.1.0/24"

# Client-only setup
sudo nfsctl setup --yes --type client

# Preview without changes
sudo nfsctl --dry-run setup --yes
```

| Flag | Description |
|------|-------------|
| `--type server\|client` | Installation type (default: `server`) |
| `--path PATH` | Export path |
| `--client CLIENT` | Client specifier |
| `--options OPTIONS` | NFS export options |

In non-interactive mode without `--path`, a default export is created at `/srv/nfs` for `10.0.0.0/8` with options `rw,sync,no_subtree_check`.

#### `install` -- Install Packages

```bash
sudo nfsctl install --type server
sudo nfsctl install --type client
```

| Flag | Description |
|------|-------------|
| `--type server\|client` | Installation type (default: `server`) |

Server installs: `nfs-kernel-server`, `nfs-common`. Client installs: `nfs-common`.

#### `export add` -- Add an NFS Export

```bash
# Interactive
sudo nfsctl export add

# Non-interactive
sudo nfsctl export add --yes \
  --path /srv/nfs/data \
  --client "192.168.1.0/24" \
  --options "rw,sync,no_subtree_check"
```

| Flag | Description |
|------|-------------|
| `--path PATH` | Export path (default: `/srv/nfs`) |
| `--client CLIENT` | Client specifier (default: `10.0.0.0/8`) |
| `--options OPTIONS` | NFS export options (default: `rw,sync,no_subtree_check`) |
| `--create-dir` | Create the directory if it does not exist |
| `--no-create-dir` | Do not create the directory |

If the export path does not exist, the tool prompts to create it (or creates it automatically in non-interactive mode unless `--no-create-dir` is specified).

If an entry with the same path and client already exists with different options, the options are updated in place. If the entry is identical, no change is made.

After adding, the tool prompts to apply exports via `exportfs -ra`.

#### `export remove` -- Remove an NFS Export

```bash
# Interactive (shows numbered list of managed exports to pick from)
sudo nfsctl export remove

# Non-interactive
sudo nfsctl export remove --yes --path /srv/nfs/data --client "192.168.1.0/24"
```

| Flag | Description |
|------|-------------|
| `--path PATH` | Export path to remove |
| `--client CLIENT` | Client specifier to remove |

Only removes lines tagged `# Managed by nfsctl`. Unmanaged exports are never touched.

#### `export list` -- List Exports

```bash
# Table format (managed exports only)
nfsctl export list

# All exports including unmanaged
nfsctl export list --all

# JSON output
nfsctl export list --json
```

| Flag | Description |
|------|-------------|
| `--all` | Include unmanaged exports |
| `--json` | Output as JSON array |

Does not require root. JSON output format:

```json
[
  {"path": "/srv/nfs", "client": "10.0.0.0/8", "options": "rw,sync,no_subtree_check"},
  {"path": "/srv/data", "client": "192.168.1.0/24", "options": "ro,sync"}
]
```

#### `export apply` -- Apply Exports

```bash
sudo nfsctl export apply
```

Runs `exportfs -ra` to reload `/etc/exports`. No flags.

#### `service` -- Manage NFS Service

```bash
sudo nfsctl service start
sudo nfsctl service stop
sudo nfsctl service restart
sudo nfsctl service enable
sudo nfsctl service disable
nfsctl service status
```

| Flag | Description |
|------|-------------|
| `--service NAME` | Override service name (default: `nfs-kernel-server`) |

The `status` action does not require root. All other actions do.

`start` and `enable` are idempotent -- they check current state first and skip if already running/enabled. `restart` always restarts.

#### `firewall` -- Configure Firewall Rules

```bash
# Add NFS firewall rules
sudo nfsctl firewall

# Remove NFS firewall rules
sudo nfsctl firewall --remove
```

| Flag | Description |
|------|-------------|
| `--remove` | Remove NFS rules instead of adding them |

Auto-detects the active firewall:

| Firewall | Detection | Behavior |
|----------|-----------|----------|
| **ufw** | `ufw status` shows "active" | `ufw allow <port>/<proto>` for each port |
| **nftables** | `nft list ruleset` contains tables | Inserts into existing `inet filter input` chain if present; otherwise creates `inet nfsctl` table |
| **none** | Neither detected | Logs "No active firewall detected" and skips |

Ports opened (TCP and UDP for each):

| Port | Service |
|------|---------|
| 2049 | NFS |
| 111 | rpcbind |
| 20048 | mountd |

#### `status` -- Status Overview

```bash
sudo nfsctl status
```

Displays six sections: installed packages, service states, managed exports, active exports (from `exportfs -v`), firewall rules, and listening NFS ports. Works without root but shows a warning that some information may be incomplete.

### Interactive vs Non-Interactive Mode

Every command that collects input supports two modes:

- **Interactive** -- when stdin is a TTY and `--yes` is not set, the tool prompts for each value with validation and defaults shown in brackets
- **Non-interactive** -- when stdin is not a TTY or `--yes` is set, the tool uses CLI flags or falls back to defaults

Values are resolved in priority order:

1. CLI flag (e.g., `--path /srv/nfs`)
2. Interactive prompt (only if TTY and no `--yes`)
3. Default from configuration

### Dry Run

`--dry-run` prevents all mutations while still performing validation and state checks:

```bash
sudo nfsctl --dry-run setup --yes
```

| Operation | Skipped in dry run | Still performed |
|-----------|-------------------|-----------------|
| Package installation | `apt-get install` | `dpkg-query` checks |
| Export file changes | File writes, `sed` edits | File reads, validation |
| Directory creation | `mkdir`, `chmod` | Path validation |
| Service management | `systemctl start/stop/...` | `systemctl is-active/is-enabled` checks |
| Firewall rules | `ufw allow`, `nft add rule` | Firewall detection, rule existence checks |
| `exportfs -ra` | Skipped | -- |

## Configuration

All defaults are in `conf/defaults.conf`. Override any value by creating `/etc/nfsctl/defaults.conf`:

| Variable | Default | Description |
|----------|---------|-------------|
| `DEFAULT_EXPORT_OPTIONS` | `rw,sync,no_subtree_check` | NFS options for new exports |
| `DEFAULT_CLIENT` | `10.0.0.0/8` | Client specifier for new exports |
| `DEFAULT_EXPORT_PATH` | `/srv/nfs` | Default export directory |
| `NFS_SERVER_PACKAGES` | `nfs-kernel-server nfs-common` | Packages for server install |
| `NFS_CLIENT_PACKAGES` | `nfs-common` | Packages for client install |
| `NFS_SERVER_SERVICE` | `nfs-kernel-server` | systemd service name |
| `NFS_PORT` | `2049` | NFS port (firewall) |
| `MOUNTD_PORT` | `20048` | mountd port (firewall) |
| `RPCBIND_PORT` | `111` | rpcbind port (firewall) |
| `LOCK_FILE` | `/var/lock/nfsctl.lock` | Lock file path |
| `EXPORTS_FILE` | `/etc/exports` | Exports file path |
| `MANAGED_TAG` | `# Managed by nfsctl` | Tag appended to managed lines |
| `BACKUP_DIR` | `/var/backups/nfsctl` | Backup directory |

Loading order: bundled `conf/defaults.conf` first, then `/etc/nfsctl/defaults.conf` (system overrides win).

## Architecture

### Project Structure

```
nfsctl                      Main dispatcher (global flags, command routing)
lib/
  common.sh                 Logging, error handling, locking, root check, config
  wizard.sh                 Dual-mode prompt framework (interactive + CLI flags)
  validation.sh             IP, CIDR, hostname, path, NFS option validators
  packages.sh               Idempotent apt package management
  services.sh               Idempotent systemd service management
  exports.sh                /etc/exports parsing, add, remove, apply
  firewall.sh               ufw/nftables rule management
commands/
  setup.sh                  Full guided setup wizard
  install.sh                Package installation
  export-add.sh             Add export
  export-remove.sh          Remove export
  export-list.sh            List exports (table/JSON)
  export-apply.sh           Apply exports (exportfs -ra)
  service.sh                Service management
  firewall.sh               Firewall command
  status.sh                 Status overview
conf/
  defaults.conf             Default configuration values
tests/
  helpers/mock.sh           Test framework and mock helpers
  test_validation.sh        Validator unit tests (51 assertions)
  test_exports.sh           Exports parsing tests (16 assertions)
  test_idempotency.sh       Idempotency integration tests (14 assertions)
  test_json.sh              JSON output and parser tests (30 assertions)
```

### Design Principles

**Idempotency.** Every mutation follows: check state, skip if already done, check dry-run, act, verify. For example, `add_export_entry` checks if the exact line already exists (skip), if the path+client exists with different options (update in place), or if it's new (append). The "already done" semantics are specific to each operation.

**Managed exports.** Lines written to `/etc/exports` are tagged with `# Managed by nfsctl`. All reads, updates, and deletes filter on this tag. Unmanaged lines are preserved verbatim. Each managed entry uses one client per line for unambiguous parsing.

**Locking.** The `/etc/exports` file is protected by an `flock`-based lock (`/var/lock/nfsctl.lock`, fd 200, non-blocking). Only export mutations acquire the lock. A TOCTOU-safe pattern is used: pre-lock check for fast idempotent skip, then acquire lock, backup, re-check under lock, mutate, release.

**Backups.** Before every `/etc/exports` modification, the file is copied to `/var/backups/nfsctl/exports.<timestamp>` (nanosecond resolution) using `cp -a` to preserve permissions. Backups are created under the lock, after acquisition and before mutation.

**Root escalation.** `require_root` detects non-root and re-execs the entire original command line via `sudo -E`. The original `argv` is saved by the dispatcher at startup, so all flags and arguments (including `--verbose`, `--dry-run`, `--yes`) are preserved across the re-exec.

### Validation Rules

**IP addresses:** Four decimal octets (0-255), no leading zeros (rejects `01`, `08`), no trailing dot.

**CIDR:** Valid IP followed by `/0` through `/32`.

**Hostnames:** RFC 1123. Labels 1-63 chars of `[a-zA-Z0-9-]`, no leading/trailing hyphen, max 253 chars total, no trailing dot.

**NFS client specifiers:** Accepts `*` (wildcard), `*.domain.com`, CIDR, IPv4, `@netgroup`, and hostnames. Rejects all-numeric dotted strings like `10.0` or `192.168.1` (likely truncated IPs).

**Export paths:** Absolute, no double slashes, no trailing slash (except `/`), characters restricted to `[a-zA-Z0-9/_.-]`.

**Export options:** Comma-separated list of known NFS options. No leading, trailing, or double commas. Key=value options (e.g., `anonuid=1000`) are accepted for known keys. Known options:

```
rw  ro  sync  async  no_subtree_check  subtree_check
no_root_squash  root_squash  all_squash  no_all_squash
insecure  secure  wdelay  no_wdelay  crossmnt
anonuid  anongid  fsid  sec
nohide  hide  mp  mountpoint  pnfs  no_pnfs  security_label
nordirplus  no_acl
```

## Testing

Tests run without root and use temporary files:

```bash
bash tests/test_validation.sh     # 51 assertions — IP, CIDR, hostname, client, path, options
bash tests/test_exports.sh        # 16 assertions — add, remove, update, list, idempotency, backups
bash tests/test_idempotency.sh    # 14 assertions — repeated ops, cycles, dry-run, multi-client
bash tests/test_json.sh           # 30 assertions — JSON escaping, line parsing, end-to-end output
```

Run all suites:

```bash
for t in tests/test_*.sh; do echo "=== $t ===" && bash "$t" || exit 1; done
```

All 111 assertions should pass with zero failures.

## Error Handling

- **Unknown flags:** `die "Unknown flag: <flag>"` (exit 1)
- **Missing flag values:** `die "Flag '<flag>' requires a value."` (exit 1) -- catches `--path` without an argument
- **Validation failures:** Non-interactive mode exits with a clear error. Interactive mode shows "Invalid input. Please try again." and re-prompts.
- **Missing required values:** Non-interactive mode without a required value and no default: `die "No value provided for '<key>' and no default available. Use --<flag> flag or run interactively."` (exit 1)
- **Failed operations:** Package install, service start/enable/restart are verified after execution. If verification fails: `die "Failed to <action> <target>"` (exit 1)
- **Lock contention:** `die "Another nfsctl process is running (lock: <lockfile>)"` (exit 1)
- **Not root, no sudo:** `die "This command must be run as root."` (exit 1)

All production code uses `set -euo pipefail`. Test code uses `set -uo pipefail` (without `-e`) so assertion failures are reported rather than causing silent aborts.

## Security Considerations

- **Default client is `10.0.0.0/8`**, not `*`. Exports are not world-accessible by default. Review and restrict the client specifier for your network.
- **Managed tag isolation.** Only lines tagged `# Managed by nfsctl` are modified or removed. Hand-configured exports in `/etc/exports` are never touched.
- **Dry-run before apply.** Use `--dry-run` to preview changes before committing, especially in automation.
- **Firewall integration.** When an existing nftables filter chain is detected, rules are inserted there (tagged with `comment "nfsctl"`) rather than creating a separate table that might be bypassed.
- **`sudo -E` caveat.** Environment variables (`VERBOSE`, `DRY_RUN`, `YES`) may be stripped by `sudoers` `env_reset`. CLI flags (`--verbose`, `--dry-run`, `--yes`) are always preserved because the full original command line is re-parsed after re-exec.
- **Config file sourcing.** Both `conf/defaults.conf` and `/etc/nfsctl/defaults.conf` are sourced as Bash. Ensure these files are root-owned and not world-writable.

## License

TBD
