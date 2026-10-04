# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the plugin
version follows [semantic versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.2.0] — 2026-10-04

### Added

- `read-tsf-sync` installs and updates the skill on machines with or
  without GitHub. It is a bash script in the plugin's `bin/`, with a
  PowerShell twin (`read-tsf-sync.ps1` and a `.cmd` launcher) for Windows
  PowerShell 5.1 and later. Each run picks its source: an archive given on
  the command line, else GitHub when it answers, else the newest release
  archive in the current directory or in Downloads. Archives are checked
  against their `.sha256`. Local edits are kept across updates, and an edit
  that collides with the new release is kept under `pending/`.
- `read-tsf-sync contribute` writes a Markdown document that the user reads
  and e-mails themselves. It holds a summary, an evidence table (platform,
  PAN-OS version, what was checked, what it showed), the changed files, the
  checks that ran, a diff and the full text. A change to the skill's
  documents needs evidence. Before anything is written, the new lines and
  the text around them are checked:
  - against the customer-data patterns;
  - for domain names;
  - for the hostname, serial, domain and addresses of the analyzed TSF
    (`--tsf`);
  - against a local `denylist.txt`.

  A pull request is opened instead only from a git clone with a logged-in
  `gh`, and only with `--yes`; its description is the same summary and
  evidence. Neither path ever carries a binary or a file from outside the
  skill.
- `tools/check-no-customer-data.sh` also catches PAN-OS serials, MAC
  addresses outside the documentation block, values of config elements that
  hold names and secrets, and PAN-OS encrypted values.
- `tools/intake.sh` turns a received contribution into a pull request under
  the contributor's name. `--dry-run` only checks it. `tools/pack.sh` builds
  the offline archive, and a release workflow attaches it to every `v*` tag.
- A `read-tsf-sync` skill, a few lines long, so that Claude can run an
  update or a contribution when asked.
- `tools/test-sync.sh` runs either script end to end in a sandbox. CI runs
  it with bash and PowerShell 7 on Linux, and with Windows PowerShell 5.1
  and Git Bash on Windows.

### Fixed

- `README.md` described the symptom map as covering "sessions" and
  "management plane", which are not rows of it, and omitted seven that are.
  It now names the sixteen domains the table actually holds.

## [1.1.1] — 2026-09-20

### Fixed

- Two table cells were split by unescaped pipes inside inline code:
  `grep -E "panic|oops|segfault|watchdog|Killed process"` in the crash row
  and `before|after-sp-imported.xml` in the Panorama row. Markdown read
  those pipes as column separators, so the crash row rendered as nine
  columns and scattered its interpretation across cells belonging to no
  header. Both now escape them, as the memory and auth rows already did.
- `README.md` documented `claude plugin update read-tsf`, which the CLI
  answers with `Plugin "read-tsf" not found`. The qualified name
  `read-tsf@tbortolossi` is what it accepts.

### Changed

- `README.md` lists what the 1.1.0 additions cover — the inventory pass,
  clock trust, log forwarding, and the log names that exist on no archive —
  and points at this changelog.

## [1.1.0] — 2026-09-20

First public release. Everything below was verified against real archives:
an extracted PA-440 and ten anonymized tech support files covering the
PA-3200 family, a PA-5200, two PA-7000 chassis and several single-dataplane
platforms, PAN-OS 10.2 through 12.1.

### Added

- Step 0b — an inventory pass before any reading: where the bytes are, which
  planes exist, what the zero-byte files say, and the time window each
  daemon's rotations actually cover. A file left unread should fall into one
  of five stated reasons.
- Clock trust: `var/log/ntpstats/{loopstats,peerstats}`, how to read a
  Modified Julian Day, and what an offset step does to cross-source
  correlation.
- Log forwarding to Strata Logging Service / Cortex Data Lake — `icd.log`
  (control path, names the region) and `icd_dp.log` (data path, errors
  only). A total forwarding outage that no other file in the archive
  reports.
- Interface flaps dated to the millisecond and counted in `qtrace_routed.log`,
  with the OSPF re-originations they caused.
- Device health monitors (`sysdagent.log`), SNMP (`snmpd.log`), keystore and
  certificates (`cryptod.log`, `dsms-certificates.log`), MP↔DP plumbing
  (`pan_comm_0.log`, `pan_dha.log`), daemon supervision (`supervisor.log`,
  `md-startscript.log`), SD-WAN and LSVPN, IoT, directory sync, the plugin
  bus, `dmesg`, `syslog-system`, `raid.log` and `disk-migration.log`.
- Panorama sync state: `opt/pancfg/mgmt/{template,sp}/` with their
  `push-version.txt`, `push-checksum.txt` and RCS audit histories.
- The GlobalProtect portal's nginx front end, `var/log/nginx/sslvpn_access.log`.
- "Names that are not in any TSF" — published log names that exist on no
  archive of the corpus, and what is there instead.
- `tools/coverage.sh`, which lists the file families of an extracted TSF that
  the documents do not account for.
- `CLAUDE.md`, `CONTRIBUTING.md`, `SECURITY.md`, `.gitignore` and CI.

### Fixed

- `var/log/nginx/` rotates to `.zip`, not `.gz`, and `.log.0.gz` is a
  rotation rather than the live file.
- The JSON log family does not always carry an RFC 3339 timestamp:
  `icd_dp.log` puts a yearless syslog clock inside the JSON envelope, so a
  date comparison there silently matches nothing.
- Two dead references — a guide path that does not exist in this repository,
  and an internal project that is not public.

## [1.0.0] — 2026-09-20

- The skill, extracted from `tsf-anonymizer` with its history and
  restructured as a plugin marketplace.
