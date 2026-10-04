#!/usr/bin/env bash
# Exercise read-tsf-sync end to end in a throwaway sandbox.
#
#   tools/test-sync.sh bash        the bash script
#   tools/test-sync.sh ps          the PowerShell script ($PWSH, default
#                                  powershell.exe on Windows, pwsh elsewhere)
#
# Three releases are built from the current tree, then: an offline install
# found by auto-detection, edits that must and must not count, a refused
# leak, a contribution file, its intake, an offline update that keeps one
# edit and parks a conflicting one, a refused downgrade and checksum, and a
# switch to a git clone. Nothing touches the network, Claude Code or $HOME.
# KEEP=1 leaves the sandbox behind and prints where it is.
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
impl=${1:-}
case $impl in bash|ps) ;; *) sed -n '2,6p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2; exit 2 ;; esac

windows=0; case $(uname -s) in MINGW*|MSYS*|CYGWIN*) windows=1 ;; esac
w() { if [ $windows = 1 ]; then cygpath -w "$1"; else printf '%s' "$1"; fi; }
if [ $windows = 1 ]; then pwsh=${PWSH:-powershell.exe}; else pwsh=${PWSH:-pwsh}; fi

T=$(mktemp -d)
if [ -n "${KEEP:-}" ]; then echo "sandbox: $T"; else trap 'rm -rf "$T"' EXIT; fi
cd "$T" || exit 2
mkdir -p fh
export HOME=$T/fh GIT_CONFIG_GLOBAL=$T/gitconfig READ_TSF_NO_REGISTER=1 GIT_TERMINAL_PROMPT=0
READ_TSF_HOME=$(w "$T/rts"); export READ_TSF_HOME
git config --global user.name ci; git config --global user.email ci@example.com
git config --global init.defaultBranch main; git config --global core.autocrlf false

# Three releases of the current tree: 1.2.0, then 1.2.1 changing one file, then 1.2.2.
mkdir src && (cd "$here" && git ls-files -co --exclude-standard | tar -cf - -T -) | (cd src && tar -xf -)
manifest=plugins/read-tsf/.claude-plugin/plugin.json
bump() { sed -i "s/\"version\": *\"[^\"]*\"/\"version\": \"$1\"/" "$manifest"; git commit -qam "$1"; git tag "v$1"; }
(cd src && git init -q && git add -A && git commit -qm base && bump 1.2.0 && tools/pack.sh >/dev/null &&
  sed -i '1s/^/# upstream changed\n/' plugins/read-tsf/skills/read-tsf-sync/SKILL.md && bump 1.2.1 && tools/pack.sh >/dev/null &&
  bump 1.2.2) || { echo "could not build the test releases" >&2; exit 2; }
git clone -q --bare src origin.git

if [ "$impl" = bash ]; then
  run()   { rts/repo/plugins/read-tsf/bin/read-tsf-sync "$@"; }
  first() { src/plugins/read-tsf/bin/read-tsf-sync "$@"; }
else
  run()   { "$pwsh" -NoProfile -File "$(w rts/repo/plugins/read-tsf/bin/read-tsf-sync.ps1)" "$@"; }
  first() { "$pwsh" -NoProfile -File "$(w src/plugins/read-tsf/bin/read-tsf-sync.ps1)" "$@"; }
fi
G=rts/repo/plugins/read-tsf/skills/read-tsf
fails=0
check() {   # on failure, show the output the check was reading
  if eval "$2"; then echo "ok   $1"; return; fi
  echo "FAIL $1"; fails=$((fails + 1))
  local last
  # shellcheck disable=SC2012  # the o.* names are this script's own
  last=$(ls -t o.* 2>/dev/null | head -1)
  [ -z "$last" ] || sed 's/^/     | /' "$last" | tail -25
}
nowhere=https://nowhere.invalid/read-tsf.git

cp src/dist/read-tsf-1.2.0.tar.gz src/dist/read-tsf-1.2.0.tar.gz.sha256 .
READ_TSF_REPO_URL=$nowhere first install > o.install 2>&1
check "offline install found by auto-detection" "grep -q 'offline mode' o.install"

{ printf '\357\273\277'; sed 's/$/\r/' "$G/TSF-GUIDE.md"; } > g && mv g "$G/TSF-GUIDE.md"
run status > o.status 2>&1
check "CRLF and BOM alone are not an edit" "grep -q 'local edits:  none' o.status"

printf 'A verified pointer.\r\n' >> "$G/TSF-GUIDE.md"
echo secret > rts/repo/plugins/read-tsf/debug.log
printf 'a\0b' > "$G/blob.md"
echo "# new" > "$G/NOTES.md"
echo edit >> rts/repo/plugins/read-tsf/skills/read-tsf-sync/SKILL.md
echo "Seen on $(printf %s.%s 198.18 4.20)" > "$G/LEAK.md"   # assembled so the repository check does not trip on it
run contribute -m leak --no-evidence test --author "Jane Doe <jane@example.com>" > o.leak 2>&1
check "an address outside the documentation ranges is refused" "grep -q 'nothing was written' o.leak && ! ls ./*.md >/dev/null 2>&1"
rm "$G/LEAK.md"

ev="PA-440 ;; 11.1.4 ;; grep -c 'IKE SA' var/log/pan/ikemgr.log ;; one line per rekey"
run contribute -m "no evidence" --author "Jane Doe <jane@example.com>" > o.noev 2>&1
check "a change to the skill without evidence is refused" "grep -q 'say where it was verified' o.noev"

echo "Logs go to collector.acme-corp.fr." >> "$G/NOTES.md"
run contribute -m x --evidence "$ev" --author "Jane Doe <jane@example.com>" > o.domain 2>&1
check "a customer domain on a new line is refused" "grep -q 'domain name: collector.acme-corp.fr' o.domain"
echo "# new" > "$G/NOTES.md"

mkdir -p tsf/tmp/cli
printf 'hostname: fw-acmecorp-par01\nserial: %s\nmodel: PA-440\n' "$(printf '%s%s' 0123 45678901)" > tsf/tmp/cli/techsupport_1.txt
echo "Seen on fw-acmecorp-par01 after the upgrade." >> "$G/NOTES.md"
run contribute -m x --evidence "$ev" --tsf tsf --author "Jane Doe <jane@example.com>" > o.tsf 2>&1
check "the analyzed TSF's hostname is refused (--tsf)" "grep -q 'identifier from the TSF' o.tsf"
echo "# new" > "$G/NOTES.md"

echo "AcmeCorp" > rts/denylist.txt
run contribute -m x --evidence "PA-440 ;; 11.1.4 ;; seen at AcmeCorp ;; ok" --author "Jane Doe <jane@example.com>" > o.deny 2>&1
check "a denylisted name in the evidence is refused" "grep -q 'identifier from the TSF or the denylist' o.deny"

run contribute -m "add a pointer" -d "Seen on PA-440, 11.1." --evidence "$ev" --tsf tsf --author "Jane Doe <jane@example.com>" > o.contrib 2>&1
f=$(find . -maxdepth 1 -name 'read-tsf-*-contribution-*.md' | sed 's|^\./||' | head -1)
check "contribution document written here" "[ -n '$f' ] && grep -q '^Format: 3' '$f'"
check "it has a summary, an evidence table, the checks and a diff" "grep -q '^## Summary' '$f' && grep -q '^| PA-440 | 11.1.4 | \`grep -c' '$f' && grep -q '^## Checks run before sending' '$f' && grep -q '^+A verified pointer' '$f'"
check "the checks name the TSF identifiers" "grep -q 'identifier(s) of the analyzed TSF' '$f'"
check "a log and a binary are not carried" "! grep '^<!-- read-tsf file:' '$f' | grep -qE 'debug.log|blob.md'"
check "three files carried" "[ \$(grep -c '^<!-- read-tsf file:' '$f') = 3 ]"
check "the file has no CR" "! grep -q \$'\r' '$f'"

if command -v python3 >/dev/null && python3 -c 1 2>/dev/null; then
  git clone -q origin.git maint
  (cd maint && tools/intake.sh "../$f" --dry-run) > o.intake 2>&1
  check "intake applies it, under the contributor's name" "grep -q 'dry run: the contribution applies' o.intake && grep -q 'Jane Doe' o.intake"
  sed 's|file: add plugins/read-tsf/skills/read-tsf/NOTES.md|file: add ../../outside.md|' "$f" > evil.md
  (cd maint && tools/intake.sh ../evil.md --dry-run) > o.evil 2>&1
  check "intake refuses a path outside the skill" "grep -q 'refusing path' o.evil"
fi

run update src/dist/read-tsf-1.2.1.tar.gz > o.update 2>&1
check "update keeps an edit" "grep -q 'A verified pointer' '$G/TSF-GUIDE.md'"
check "update keeps an added file" "[ -f '$G/NOTES.md' ] && ! grep -q 'already in this release: .*NOTES' o.update"
check "a conflicting edit is parked in pending/" "grep -q 'changed upstream too' o.update && ls rts/pending/*/plugins/read-tsf/skills/read-tsf-sync/SKILL.md >/dev/null 2>&1"
check "on conflict the release wins in the tree" "head -1 rts/repo/plugins/read-tsf/skills/read-tsf-sync/SKILL.md | grep -q 'upstream changed'"
check "files that were never shipped are left alone" "[ -f rts/repo/plugins/read-tsf/debug.log ]"

run update src/dist/read-tsf-1.2.0.tar.gz > o.down 2>&1
check "a downgrade is refused" "grep -q 'older than' o.down"
cp src/dist/read-tsf-1.2.1.tar.gz bad.tar.gz; echo "00 x" > bad.tar.gz.sha256
run update bad.tar.gz > o.bad 2>&1
check "a checksum mismatch is refused" "grep -q 'checksum mismatch' o.bad"

READ_TSF_REPO_URL=$(w "$T/origin.git") run update > o.online 2>&1
check "an offline copy becomes a clone when GitHub answers" "[ -d rts/repo/.git ] && [ ! -d rts/base ] && grep -q '1.2.2' o.online"
check "edits survive the switch" "grep -q 'A verified pointer' '$G/TSF-GUIDE.md' && [ -f '$G/NOTES.md' ]"
run status > o.status2 2>&1
check "the release stamp is not an edit" "! grep -q 'read-tsf-release' o.status2"
READ_TSF_REPO_URL=$nowhere run update > o.unreach 2>&1
check "a clone does not silently go offline" "grep -q 'GitHub is not reachable' o.unreach"

if [ $fails -eq 0 ]; then echo "all checks passed ($impl)"; else echo "$fails check(s) failed ($impl)"; exit 1; fi
