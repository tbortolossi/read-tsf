# Working in this repository

`read-tsf` is a Claude Code plugin that teaches Claude to read a PAN-OS tech
support file. It ships no code that runs against a TSF: the plugin is two
markdown documents, and the analysis engine is Claude with `grep`, `awk`,
`zcat` and `unzip`. Keep it that way unless there is a reason that survives
the questions below.

```
.claude-plugin/marketplace.json           marketplace manifest (this repo is its own catalog)
plugins/read-tsf/.claude-plugin/plugin.json   plugin manifest — bump `version` on release
plugins/read-tsf/skills/read-tsf/SKILL.md     the working method, loaded in full when the skill triggers
plugins/read-tsf/skills/read-tsf/TSF-GUIDE.md the file-by-file map, read on demand
tools/coverage.sh                         which file families of a TSF the two documents account for
```

## The rule that matters most: no customer data, ever

This repository is about reading support bundles from production firewalls.
The failure mode is not a leaked credential, it is a hostname, a serial, a
public IP, a username or a case number copied out of a real TSF into an
example. Git history is permanent.

- Never commit a TSF, an extract of one, a `.tgz`, a `.pcap`, a config XML,
  a core dump or a log file. `.gitignore` blocks the obvious shapes; it is a
  net, not a guarantee.
- In examples use the placeholders the documents already use: `100.64.x.y`
  and RFC 5737 ranges (`192.0.2.x`, `198.51.100.x`, `203.0.113.x`) for
  addresses, `hostNNN` for hostnames, `userNNN` for users, `ZONE-0012` /
  `RULE-0045` / `GW-0002` for named objects, `<devicename>` and `<slot>` for
  anything else.
- Keep the pattern, drop the value. "A PA-5430 read two GRE sessions
  carrying 91 % of the packets" is the finding; the customer's serial is
  never part of it.
- A counter value, a version ladder, a log line's *shape* and a timestamp
  format are not identity and are welcome.

## What belongs in which file

`SKILL.md` is loaded into the model's context in full, every time the skill
triggers — around 55 KB today. Every addition to it is paid for on every
analysis, so it holds the **method**: the reading order, the traps, the P0
symptom table, the doctrine for buffers and counters.

`TSF-GUIDE.md` is read only when Claude follows a pointer to it. It holds
the **map**: the directory layout, the per-problem log tables including
every secondary domain, the config structure, the anonymization mapping.

When one gains a section, check whether the other needs a line. When
something could live in either, it goes in the guide.

## Evidence discipline

Every path, glob and `grep` in the two documents was checked against real
archives, and the file says so — an unqualified path was present on all of
them, a qualified one (`12.x`, `PA-3200 family`, `chassis`) only where the
qualifier says. Hold new material to the same standard:

- Open an archive and run the command before writing that it works.
- Say where the claim holds. If it was on some platforms and not others,
  that *is* the useful part.
- A name from a vendor cheat sheet is a hypothesis, not evidence. Several
  widely published PAN-OS log names exist on no archive at all — the list is
  in `TSF-GUIDE.md` §4, "Names that are not in any TSF", and it is there to
  stop the next person re-importing them.
- A wrong pointer costs more than a missing one. Deleting one is a fix.
- Prefer structural anchors (section markers, counter names, `X/Y`
  fractions) over long fixed English strings, which anonymizers mangle.

Run `tools/coverage.sh <extracted-tsf>` after a change to the map to see
what the documents still do not account for.

## Conventions

- English for everything committed: documents, commits, issues, pull
  requests. Conversations can be in any language.
- Conventional Commits, with the plugin scoped where it applies:
  `docs(read-tsf): …`, `fix(read-tsf): …`, `chore: …`.
- Semantic versioning in `plugin.json`, with a `CHANGELOG.md` entry. New
  paths or domains are a minor bump; corrections are a patch.
- Small, reviewable commits. A new log family, its guide row and its
  verification belong in one commit.
