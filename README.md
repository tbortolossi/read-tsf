# read-tsf

A Claude Code plugin that teaches Claude to read a **PAN-OS tech support file**.

A TSF is a gzipped tar of 100–400 MB — around 500 files once extracted: the
device configuration, every daemon log with its rotations, and the captured
output of several hundred `show` and `debug` commands. Knowing which of those
files answers a given symptom is the whole problem. This plugin carries that
map, plus the reading doctrine that goes with it.

Every path and every `grep` in the skill was re-checked against ten real
TSFs — PA-440, PA-1420, PA-3220 (×2), PA-3410, PA-5250 (×2), PA-5430, PA-7050,
PA-7080 — on PAN-OS 10.2.9 through 12.1.4. Where a file exists only on some
platforms, the qualifier says so; an unqualified path was present on all ten.

## Install

```bash
claude plugin marketplace add tbortolossi/read-tsf
claude plugin install read-tsf@tbortolossi
```

Installing at the default `user` scope makes the skill available in every
project on the machine. Use `--scope project` instead to declare it in a
repository's own settings, so anyone who clones that repository gets it too.

Restart Claude Code, then point it at an archive:

> Analyze this tech support file: `~/cases/01234567/techsupport.tgz` — the
> IPsec tunnel to site B drops every night.

## Update

```bash
claude plugin marketplace update tbortolossi
claude plugin update read-tsf@tbortolossi
```

Updates take effect after a restart.

## Machines without GitHub

`read-tsf-sync` ships in the plugin. Use `bin/read-tsf-sync` with bash on
Linux, macOS or Git Bash, and `bin/read-tsf-sync.cmd` or `.ps1` on Windows.
It keeps a working copy of this repository in `~/.local/share/read-tsf/repo`
(`%LOCALAPPDATA%\read-tsf\repo` on Windows) and registers it with Claude Code.
The two scripts take the same commands and share the same copy.

Where updates come from is detected on each run:

1. an archive given on the command line;
2. otherwise GitHub, if git is installed and github.com answers;
3. otherwise the newest `read-tsf-X.Y.Z.tar.gz` in the current directory or
   in Downloads.

Every [release](https://github.com/tbortolossi/read-tsf/releases) carries
that archive and its `.sha256`. Copy both by USB or e-mail; the checksum is
checked when it travels with the archive. Offline, nothing is needed beyond
`tar`, which Windows 10 and later include.

```bash
# first time, offline: unpack once to get the script
tar -xzf read-tsf-1.2.0.tar.gz
read-tsf-1.2.0/plugins/read-tsf/bin/read-tsf-sync install read-tsf-1.2.0.tar.gz
# later
read-tsf-sync update                 # GitHub, or the newest archive found
read-tsf-sync status                 # mode, version, local edits
```

```bat
:: Windows
tar -xzf read-tsf-1.2.0.tar.gz
read-tsf-1.2.0\plugins\read-tsf\bin\read-tsf-sync.cmd install read-tsf-1.2.0.tar.gz
%LOCALAPPDATA%\read-tsf\read-tsf-sync.cmd update
```

`install` will not replace an existing `tbortolossi` marketplace, such as
the GitHub one above, unless it is given `--replace`. `update` keeps local
edits across versions. An edit that collides with a change in the new
release is kept under `pending/`, and the release's version stays in the tree.

### Sending a correction back

Edit the working copy, then:

```bash
read-tsf-sync contribute -m "fix the GlobalProtect log path on 11.1" \
  -d "The 11.1 path moved under var/log/pan/gp/." \
  --evidence "PA-3220 ;; 11.1.6 ;; ls var/log/pan/gp/ ;; gpsvc.log present, old path absent" \
  --evidence "PA-440 ;; 11.2.3 ;; same ;; same" \
  --tsf ~/cases/extracted-tsf \
  --author "First Last <you@example.com>"
```

This writes a **Markdown document** in the current directory. You read it,
then e-mail it yourself to the maintainer. It contains:

- a summary;
- an **evidence table**: platform, PAN-OS version, what was checked, what
  it showed;
- the list of files with their line counts;
- the checks that ran;
- a diff;
- the full text of each changed file, which `tools/intake.sh` reads.

Nothing in it is compressed or encoded. A change to the skill's two
documents needs at least one `--evidence` line, or `--no-evidence "typo"`
for a change that makes no new claim.

**Nothing identifying a customer goes out.** Before the document is
written, the lines the edit adds, plus the summary and evidence, are checked
against:

- the repository's patterns: addresses outside the documentation ranges,
  e-mail addresses, PAN-OS serials, MAC addresses, values of `<hostname>`,
  `<phash>`, `<pre-shared-key>`…, encrypted secrets (`-AQ==…`) and keys;
- any domain name that is not a documentation or vendor one;
- with `--tsf <extracted archive>`: the hostname, serial, domain and
  addresses of the device you analyzed, read from its `show system info`.
  A hostname very often carries the customer's name;
- `~/.local/share/read-tsf/denylist.txt` (`%LOCALAPPDATA%\read-tsf\denylist.txt`
  on Windows), if you keep one. Put one customer name, case-number prefix or
  internal domain per line; it never leaves the machine.

One hit and nothing is written. The document says which checks ran.

A pull request is opened instead only when all of these hold:

- the copy is a git clone;
- `gh` is installed and logged in;
- GitHub answers;
- you add `--yes` after seeing the list of files.

When it cannot open one, the script says which condition failed and writes
the document. The pull request's description is the same summary, evidence
and checks. `--offline` always writes the document.

The maintainer turns a received file into a pull request with:

```bash
tools/intake.sh read-tsf-1.2.0-contribution-20261004-101500.md --dry-run   # check only
tools/intake.sh read-tsf-1.2.0-contribution-20261004-101500.md             # branch, PR
```

### What it will and will not do

The script runs on workstations under endpoint protection, so it stays far
from what an EDR or DLP policy flags as exfiltration or a dropper:

- **Network:** only `git` and `gh`, only to the repository, and only on a
  command you typed. No `curl`, no `Invoke-WebRequest`, nothing downloaded
  and run.
- **Mail:** it never sends any. The contribution is a readable Markdown
  document that you attach yourself.
- **What can leave:** only the skill's own text files (`.md`, `.sh`,
  `.ps1`, `.json`…), at most 512 KB each, and never a binary. Anything else
  in the directory, such as a log copied there by mistake, is listed as
  "not included". Before the document is written, the customer-data
  checks above are applied to what it would carry.
- **PowerShell:** no `-ExecutionPolicy Bypass`, `-EncodedCommand`, hidden
  window, `Invoke-Expression`, base64 or `Add-Type`. If the execution policy
  refuses an unsigned local script, that is your IT's decision: allow it
  (`Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`) or sign it.
- **Persistence:** none. No scheduled task, service, registry key or PATH
  change. The only extras are the launcher `%LOCALAPPDATA%\read-tsf\read-tsf-sync.cmd`
  on Windows, and a symlink in `~/.local/bin` elsewhere when that directory
  is already on `PATH`.

No tool can promise how a given EDR will score a script. If yours blocks
something, the report should name the rule, and that is worth an issue.

## What it covers

- **Extraction and orientation** — where the command dump lives, how to read
  the device's own clock, whether that clock held still, what the archive's
  generation time does and does not tell you.
- **An inventory pass** — where the bytes are, which planes exist, and the
  time window each log's rotations actually cover, so that a file nobody
  opens is a file somebody decided not to open.
- **A symptom → file → grep map** — sixteen domains, each with what to read
  first, what to read next, and what the lines mean: VPN, HA, GlobalProtect,
  authentication, User-ID, crashes and reboots, CPU, memory, drops and
  buffers, interfaces, disk, routing, commits, content updates, log
  forwarding, Panorama.
- **Log-file aliases** — the name a log has on disk is rarely the name a PAN-OS
  engineer uses for it.
- **Reading heuristics** — counter methods, how to tell a sampled series from a
  measured one, when a zero counter means "never happened" and when it means
  "monitor-only".
- **Platform differences** — multi-dataplane and chassis layouts, PA-7000 log
  processing cards, what changed across 10.2 → 12.1.
- **Names that are not in any TSF** — published PAN-OS log lists circulate
  with files that exist on no archive at all. The list of them, and what is
  there instead, so a missing log is never reported from a name nobody
  checked.
- **Anonymized archives** — what
  [tsf-anonymizer](https://github.com/tbortolossi/tsf-anonymizer) preserves,
  what it redacts, and the over-anonymization artifacts left by its older
  versions.

Released versions and what changed in each: [CHANGELOG.md](CHANGELOG.md).

## Layout

```
.claude-plugin/marketplace.json     the marketplace manifest
plugins/read-tsf/
  .claude-plugin/plugin.json        the plugin manifest
  bin/read-tsf-sync                 install, update, contribute — bash (Linux, macOS, Git Bash)
  bin/read-tsf-sync.ps1, .cmd       the same for Windows PowerShell 5.1 / 7
  skills/read-tsf/
    SKILL.md                        the working method
    TSF-GUIDE.md                    the file-by-file map
  skills/read-tsf-sync/SKILL.md     tells Claude how to drive read-tsf-sync
tools/
  coverage.sh                       which files of a TSF the map accounts for
  pack.sh                           builds the offline release archive for a tag
  intake.sh, intake_parse.py        turns an e-mailed contribution into a pull request
  test-sync.sh                      end-to-end test of either script, run by CI on Linux and Windows
  validate.sh                       manifests, skill frontmatter, internal links
  check-no-customer-data.sh         refuses anything that came out of a real device
```

## Keeping the map honest

The skill is only worth what its pointers are worth, so every claim in it
comes from an archive somebody actually opened. `tools/coverage.sh` is how
that is checked: point it at an extracted TSF and it lists every file family
the two documents do not mention, largest first.

```bash
tools/coverage.sh ~/cases/01234567/extracted-tsf
```

Reaching 100 % is not the goal — most of a TSF is the vendor content
database, per-daemon noise and config scratch space that nobody should read.
The goal is that a file holding real bytes is either documented or a
deliberate omission, never an oversight. A family that shows up there and
matters is a contribution: add it with the platform or version that carries
it, and say how you verified it.

## Contributing

A contribution is a pointer you verified against a real archive, with the
platform or version it holds on. [CONTRIBUTING.md](CONTRIBUTING.md) is the
short version, [CLAUDE.md](CLAUDE.md) the working rules — starting with the
one that cannot be relaxed: nothing out of a real tech support file ever
enters this repository, not even anonymized.

## Related

[tsf-anonymizer](https://github.com/tbortolossi/tsf-anonymizer) — anonymize a
TSF with consistent pseudonyms before sharing it, and prove by an independent
compare that nothing but identifiers was lost. This skill was extracted from
that repository, with its history.

## License

Apache-2.0. See [LICENSE](LICENSE).
