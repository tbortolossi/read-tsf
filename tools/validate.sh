#!/usr/bin/env bash
# Check that the marketplace, the plugin and the skill still hold together:
# manifests parse, required keys are present, declared paths exist, the skill
# carries usable frontmatter, and every relative link resolves.
set -uo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" || exit 2

python3 - <<'PY'
import json, os, re, sys

fail = []
def check(cond, msg):
    if not cond:
        fail.append(msg)

# --- manifests -------------------------------------------------------------
try:
    market = json.load(open(".claude-plugin/marketplace.json"))
except Exception as e:
    print(f"marketplace.json does not parse: {e}"); sys.exit(1)

check("name" in market, "marketplace.json: missing 'name'")
check(isinstance(market.get("plugins"), list) and market["plugins"],
      "marketplace.json: no plugins listed")

for entry in market.get("plugins", []):
    src = entry.get("source", "")
    check(bool(src), f"marketplace.json: {entry.get('name')} has no source")
    root = os.path.normpath(src)
    manifest = os.path.join(root, ".claude-plugin", "plugin.json")
    check(os.path.isfile(manifest), f"missing plugin manifest: {manifest}")
    if not os.path.isfile(manifest):
        continue
    try:
        plugin = json.load(open(manifest))
    except Exception as e:
        fail.append(f"{manifest} does not parse: {e}"); continue
    for key in ("name", "version", "description"):
        check(key in plugin, f"{manifest}: missing '{key}'")
    check(plugin.get("name") == entry.get("name"),
          f"{manifest}: name '{plugin.get('name')}' != marketplace entry '{entry.get('name')}'")
    check(re.fullmatch(r"\d+\.\d+\.\d+", plugin.get("version", "")) is not None,
          f"{manifest}: version '{plugin.get('version')}' is not semver")

    # --- skills ------------------------------------------------------------
    skills = os.path.join(root, "skills")
    check(os.path.isdir(skills), f"{root}: no skills directory")
    for name in sorted(os.listdir(skills)) if os.path.isdir(skills) else []:
        md = os.path.join(skills, name, "SKILL.md")
        check(os.path.isfile(md), f"{skills}/{name}: no SKILL.md")
        if not os.path.isfile(md):
            continue
        text = open(md, encoding="utf-8").read()
        m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
        check(m is not None, f"{md}: no YAML frontmatter")
        if m:
            head = m.group(1)
            check(re.search(r"^name:\s*\S", head, re.M) is not None, f"{md}: frontmatter has no name")
            desc = re.search(r"^description:\s*(.*)$", head, re.M | re.S)
            check(desc is not None and len(desc.group(1).strip()) > 40,
                  f"{md}: description missing or too short to trigger reliably")

# --- relative links --------------------------------------------------------
for dirpath, dirs, files in os.walk("."):
    dirs[:] = [d for d in dirs if d not in (".git", ".github")]
    for f in files:
        if not f.endswith(".md"):
            continue
        p = os.path.join(dirpath, f)
        for target in re.findall(r"\]\(([^)]+)\)", open(p, encoding="utf-8").read()):
            if target.startswith(("http://", "https://", "#", "mailto:")):
                continue
            resolved = os.path.normpath(os.path.join(dirpath, target.split("#")[0]))
            check(os.path.exists(resolved), f"{p}: broken link -> {target}")

if fail:
    print("\n".join(sorted(set(fail))))
    print(f"\n{len(set(fail))} problem(s)")
    sys.exit(1)
print("marketplace, plugin, skill and links all check out")
PY
