#!/usr/bin/env bash
# Turn a contribution received by e-mail into a pull request.
#
#   tools/intake.sh <read-tsf-X.Y.Z-contribution-YYYYMMDD-HHMMSS.md> [--no-pr | --dry-run]
#
# --no-pr stops before pushing and leaves the branch; --dry-run checks that
# the file applies and passes the checks, then removes the branch again.
#
# The file is what `read-tsf-sync contribute` (bash or PowerShell) writes on
# a machine without GitHub: a Markdown document whose summary, evidence and
# checks become the pull request's description, followed by the full text
# of each changed file. Each file is written onto a branch cut from the
# commit the contributor started from — after checking that their starting
# version is the one in that commit — then checked for customer data and
# structure, committed under the contributor's name, rebased onto
# origin/main, pushed and opened as a pull request. Read the diff it prints
# before merging: the checks are a net, not a review.
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" || exit 2

file=${1:-}; no_pr=0; dry=0
case ${2:-} in --no-pr) no_pr=1 ;; --dry-run) dry=1 ;; esac
[ -f "$file" ] || { sed -n '2,7p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2; exit 2; }
[ -z "$(git status --porcelain)" ] || { echo "working tree not clean" >&2; exit 1; }

meta=$(mktemp); trap 'rm -f "$meta"' EXIT
# Parse and validate without touching the tree; prints shell-safe assignments.
python3 "$(dirname "${BASH_SOURCE[0]}")/intake_parse.py" "$file" > "$meta"
files=() from="" subject="" base_version="" base_commit="" summary="" stage=""
# shellcheck disable=SC1090
. "$meta"
trap 'rm -f "$meta"; rm -rf "$stage"' EXIT

# Same normalization as the contributor's side: no BOM, no CR, final LF.
norm_sha() { LC_ALL=C tr -d '\r' | LC_ALL=C awk 'NR==1 && substr($0,1,3)=="\357\273\277" {$0=substr($0,4)} {print}' | sha256sum | awk '{print $1}'; }

[ $dry = 1 ] || git fetch --quiet --tags origin
base=$base_commit
git cat-file -e "$base^{commit}" 2>/dev/null || base=v$base_version
git cat-file -e "$base^{commit}" 2>/dev/null || { echo "neither $base_commit nor v$base_version is known" >&2; exit 1; }

branch=contrib/$(basename "$file" .md)
start=$(git rev-parse --abbrev-ref HEAD)
git switch --quiet -c "$branch" "$base"
trap 'rm -f "$meta"; rm -rf "$stage"; echo "left on $branch; git switch $start && git branch -D $branch to drop it" >&2' ERR

touched=()
for ((n = 0; n < ${#files[@]}; n += 4)); do
  op=${files[n]} path=${files[n+1]} want=${files[n+2]} src=${files[n+3]}
  if [ -f "$path" ]; then have=$(norm_sha < "$path"); else have=-; fi
  [ "$have" = "$want" ] || { echo "$path: the contributor started from a different version than $base" >&2; false; }
  case $op in
    delete) git rm -q -- "$path" ;;
    *) mkdir -p "$(dirname "$path")"; cp "$src" "$path"; git add -- "$path"; touched+=("$path") ;;
  esac
done

[ ${#touched[@]} -eq 0 ] || tools/check-no-customer-data.sh "${touched[@]}"
tools/validate.sh

git commit --quiet --author="$from" -m "$subject" ${summary:+-m "$summary"}
if [ $dry = 1 ]; then
  trap - ERR
  git --no-pager show --stat --format='%an <%ae>%n%s' HEAD
  git switch --quiet "$start"; git branch -q -D "$branch"
  echo "dry run: the contribution applies and passes the checks"
  exit 0
fi
git rebase --quiet origin/main
trap - ERR

git --no-pager show --stat HEAD
[ $no_pr = 1 ] && { echo "branch $branch ready; not pushed (--no-pr)"; exit 0; }

git push --quiet -u origin "$branch"
# shellcheck disable=SC2016  # the backticks are Markdown
printf '\n\nReceived by e-mail from %s, made against read-tsf %s; applied with `tools/intake.sh`.\n' \
  "${from% <*}" "$base_version" >> "$stage/pr-body.md"
gh pr create --base main --head "$branch" --title "$subject" --body-file "$stage/pr-body.md"
git switch --quiet "$start"
