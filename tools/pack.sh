#!/usr/bin/env bash
# Build the offline release archive for a tagged version.
#
#   tools/pack.sh [vX.Y.Z]        (default: the version in plugin.json)
#
# Writes dist/read-tsf-X.Y.Z.tar.gz and its .sha256. That pair is what an
# offline machine installs with `read-tsf-sync install <archive>` and later
# updates with `read-tsf-sync update <archive>`; send both, the checksum is
# verified when it travels with the archive.
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" || exit 2

manifest=plugins/read-tsf/.claude-plugin/plugin.json
tag=${1:-v$(sed -n 's/^ *"version": *"\([^"]*\)".*/\1/p' "$manifest" | head -1)}
git rev-parse -q --verify "refs/tags/$tag" >/dev/null || { echo "no tag $tag" >&2; exit 1; }

version=${tag#v}
tagged=$(git show "$tag:$manifest" | sed -n 's/^ *"version": *"\([^"]*\)".*/\1/p' | head -1)
[ "$tagged" = "$version" ] || { echo "$tag carries plugin version $tagged" >&2; exit 1; }

mkdir -p dist
out=dist/read-tsf-$version.tar.gz
git archive --format=tar.gz --prefix="read-tsf-$version/" -o "$out" "$tag"
(cd dist && sha256sum "read-tsf-$version.tar.gz" > "read-tsf-$version.tar.gz.sha256")
echo "$out"
echo "$out.sha256"
