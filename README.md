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

## What it covers

- **Extraction and orientation** — where the command dump lives, how to read
  the device's own clock, what the archive's generation time does and does not
  tell you.
- **A symptom → file → grep map** — VPN, HA, GlobalProtect, routing, sessions,
  dataplane, management plane, crashes.
- **Log-file aliases** — the name a log has on disk is rarely the name a PAN-OS
  engineer uses for it.
- **Reading heuristics** — counter methods, how to tell a sampled series from a
  measured one, when a zero counter means "never happened" and when it means
  "monitor-only".
- **Platform differences** — multi-dataplane and chassis layouts, PA-7000 log
  processing cards, what changed across 10.2 → 12.1.
- **Anonymized archives** — what
  [tsf-anonymizer](https://github.com/tbortolossi/tsf-anonymizer) preserves,
  what it redacts, and the over-anonymization artifacts left by its older
  versions.

## Layout

```
.claude-plugin/marketplace.json     the marketplace manifest
plugins/read-tsf/
  .claude-plugin/plugin.json        the plugin manifest
  skills/read-tsf/
    SKILL.md                        the working method
    TSF-GUIDE.md                    the file-by-file map
tools/
  coverage.sh                       which files of a TSF the map accounts for
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
