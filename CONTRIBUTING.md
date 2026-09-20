# Contributing

The value of this plugin is that its pointers are true. A contribution is
therefore a pointer you verified, with the platform or version it holds on.

## Before anything else

Read [CLAUDE.md](CLAUDE.md). It states the one rule that cannot be relaxed —
**no customer data, ever** — the split between `SKILL.md` (method, loaded in
full every time) and `TSF-GUIDE.md` (map, read on demand), and the evidence
discipline expected of new material.

## A good change

1. Open a real archive and run the command you want to document.
2. Note where it held: all platforms you tried, or only some. A qualifier is
   more useful than a confident generalization.
3. Add it to the right file, in the voice of the surrounding text.
4. Genericize. Placeholders, never a real hostname, address, serial, user or
   case number.
5. Run `tools/coverage.sh <extracted-tsf>` and check that you did not leave
   a neighbouring file family unaccounted for.
6. Commit with Conventional Commits (`docs(read-tsf): …`, `fix(read-tsf): …`)
   and add a `CHANGELOG.md` entry.

Deleting a wrong pointer is as welcome as adding a right one.

## What does not belong here

- Anything extracted from a real TSF.
- A log name taken from a vendor cheat sheet without an archive that has it.
  See "Names that are not in any TSF" in the guide for why.
- Code that parses a TSF. The plugin is deliberately documentation driving
  shell tools; a parser belongs in its own project.
