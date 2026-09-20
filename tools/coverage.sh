#!/usr/bin/env bash
# Report which files of an extracted tech support file the skill documents.
#
#   tools/coverage.sh <extracted-tsf-dir> [<extracted-tsf-dir> ...]
#
# A "family" is a file name with its rotation suffix removed, scoped to its
# directory: var/log/pan/authd.log, authd.log.old and authd.log.1.gz are one
# family. A family counts as documented when its name — or the glob form the
# docs use for it (md_*, pan_task_<n>, …) — appears in SKILL.md or
# TSF-GUIDE.md. The point is not to reach 100 %: most of a TSF is vendor data
# and per-daemon noise nobody should read. The point is that a family with
# real bytes in it and no mention anywhere is a deliberate choice or a gap,
# and this tells you which families to decide about.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
skill="$here/plugins/read-tsf/skills/read-tsf"
[ -r "$skill/SKILL.md" ] || { echo "skill not found under $skill" >&2; exit 2; }
[ $# -ge 1 ] || { sed -n '2,4p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2; exit 2; }

for d in "$@"; do
  [ -d "$d" ] || { echo "not a directory: $d" >&2; exit 2; }
done

python3 - "$skill" "$@" <<'PY'
import os, re, sys
from collections import defaultdict

skill = sys.argv[1]
docs = "".join(open(os.path.join(skill, f), encoding="utf-8", errors="replace").read()
               for f in ("SKILL.md", "TSF-GUIDE.md"))

ROT = (re.compile(r"\.(gz|zip|old)$"), re.compile(r"\.\d+$"),
       re.compile(r"-\d{4}-\d{2}-\d{2}T[\d.-]+$"))

def family(name):
    prev = None
    while prev != name:
        prev = name
        for r in ROT:
            name = r.sub("", name)
    return re.sub(r"\.log$", "", name)

def documented(name):
    cands = [name]
    m = re.match(r"^(.*?)_?\d+$", name)
    if m:
        cands += [m.group(1) + s for s in ("_*", "_<n>", "*", "")]
    # a numeric component is written <n>, N or * in the docs
    for token in ("<n>", "N", "*"):
        cands.append(re.sub(r"(?<=[._])\d+(?=[._]|$)", token, name))
    parts = name.split("_")
    for i in range(len(parts), 0, -1):
        stem = "_".join(parts[:i])
        cands += [stem + "*", stem + "_*"]
    return any(c and c in docs for c in cands)

for root in sys.argv[2:]:
    size = defaultdict(int)
    for dirpath, _, files in os.walk(root):
        rel = os.path.relpath(dirpath, root)
        rel = re.sub(r"^opt/var\.dp\d+", "opt/var.dpN", rel)
        rel = re.sub(r"^opt/var/s\d+/(dp|lfp)\d+", r"opt/var/sN/\1N", rel)
        for f in files:
            try:
                size[(rel, family(f))] += os.path.getsize(os.path.join(dirpath, f))
            except OSError:
                pass

    rows = sorted(((s, d, n, documented(n)) for (d, n), s in size.items()), reverse=True)
    known = sum(1 for r in rows if r[3])
    print(f"\n=== {root}")
    print(f"{len(rows)} families, {known} documented, {len(rows)-known} not")
    print("\nundocumented, largest first:")
    shown = 0
    for s, d, n, ok in rows:
        if ok or not s:
            continue
        path = n if d == "." else f"{d}/{n}"
        print(f"  {s/1e6:9.2f} MB  {path}")
        shown += 1
        if shown == 40:
            break
    if not shown:
        print("  (none with content)")
PY
