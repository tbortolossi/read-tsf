---
name: read-tsf-sync
description: >
  Update the read-tsf skill, or send a correction to it back to its
  maintainer — as a Markdown document with its evidence that the user
  e-mails, or as a GitHub pull request. Use when the user asks to update
  read-tsf, install it from a release archive, or fix, add or remove a
  pointer in the read-tsf skill.
---

# Updating and contributing to read-tsf

Everything goes through `read-tsf-sync`, in `../../bin/` relative to this
file. Use `read-tsf-sync` with bash on Linux, macOS or Git Bash, and
`read-tsf-sync.cmd` (it runs `read-tsf-sync.ps1`) from PowerShell or cmd on
Windows. Both take the same commands and work on the same copy.

The working copy is `~/.local/share/read-tsf/repo`, or
`%LOCALAPPDATA%\read-tsf\repo` on Windows (`$READ_TSF_HOME` overrides both).
Claude Code loads the skill from there, and it is the only place to edit it.

| The user wants | Run |
|---|---|
| To know what is installed | `read-tsf-sync status` |
| The latest version | `read-tsf-sync update` — GitHub if it answers, else the newest archive here or in Downloads |
| A version received as a file | `read-tsf-sync update read-tsf-X.Y.Z.tar.gz` (keep the `.sha256` beside it) |
| A first install | `read-tsf-sync install [<archive>]` |
| To send an edit back | `read-tsf-sync contribute …`, below |

After an install or update, tell the user to restart Claude Code. If the
output mentions `pending/`, an edit collided with the new release: tell the
user where their version is kept.

## Making a contribution

1. Read `CLAUDE.md` in the working copy and hold the edit to its rules. The
   method goes in `SKILL.md` and the map in `TSF-GUIDE.md`. Every claim says
   the platform and version it was verified on.
2. **No customer data.** Copy nothing out of the archive being analyzed: no
   customer name, hostname, address, serial, user, case number or config
   value. Keep the pattern and drop the value, and use the placeholders the
   documents use. The same rule applies to what you write in `-m`, `-d` and
   `--evidence`.
3. Edit in the working copy, then run:

```bash
read-tsf-sync contribute -m "<conventional summary>" -d "<what changed and why>" \
  --evidence "<platform> ;; <PAN-OS version> ;; <command or file checked> ;; <what it showed>" \
  --tsf <the extracted TSF this was verified on> \
  [--author "Name <mail>"]
```

- Give one `--evidence` per archive the claim was checked on. Platform and
  version are enough to identify an archive; never put its serial or
  hostname there. A change that makes no new claim (a typo, a broken link)
  takes `--no-evidence "<why>"` instead.
- Always pass `--tsf` when an archive is at hand. The script then refuses
  any line containing that device's hostname, serial, domain or addresses.
- Pass `--author` when `git config user.name` is not set.

If the script refuses, it prints each hit. Rewrite the line with a
placeholder; never work around a hit.

By default `contribute` writes one Markdown document and prints the address
to send it to. Give the user its path and the address, and suggest they read
it: summary, evidence, diff. They send it themselves; never send mail on
their behalf.

When the copy is a git clone and `gh` is logged in, `contribute` stops and
asks for `--yes` to open a pull request. Show the user the list of files it
printed, and add `--yes` only if they agree to publish them on GitHub.
Otherwise use `--offline` to write the document.
