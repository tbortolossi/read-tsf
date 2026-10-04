#!/usr/bin/env bash
# Refuse to publish anything that looks like it came out of a real device.
#
#   tools/check-no-customer-data.sh [path ...]     (default: everything tracked)
#
# This repository documents how to read production support bundles, so its
# realistic leak is not a credential but a hostname, an address, a serial or
# a user copied out of a real archive into an example. Git history is
# permanent; this runs before the commit, and again in CI.
set -uo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" || exit 2

if [ $# -gt 0 ]; then files=("$@"); else mapfile -t files < <(git ls-files); fi
[ ${#files[@]} -gt 0 ] || { echo "nothing to check"; exit 0; }

fail=0
report() { fail=1; printf '%s\n' "$1"; }

# 1. Support-bundle shapes that must never be tracked, whatever .gitignore says.
for f in "${files[@]}"; do
  case "$f" in
    *.tgz|*.tar|*.tar.gz|*.pcap|*.pcapng|*.core|*.info|*.mapping.json|*.xml,v|*.log|*.log.*)
      report "tracked file looks like device data: $f" ;;
  esac
done

# 2. Addresses outside the ranges the documents are allowed to use:
#    RFC 5737 examples, the anonymizer's 100.64/10 range, loopback, unspecified.
while IFS= read -r hit; do
  report "non-documentation IPv4 address: $hit"
done < <(
  grep -HInE '(^|[^0-9.])([0-9]{1,3}\.){3}[0-9]{1,3}([^0-9.]|$)' "${files[@]}" 2>/dev/null |
  grep -vE '(^|[^0-9.])(192\.0\.2\.|198\.51\.100\.|203\.0\.113\.|127\.0\.0\.1|0\.0\.0\.0|255\.255\.255\.)' |
  grep -vE '(^|[^0-9.])100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.'
)

# 3. Device identity that is not an address: PAN-OS serials (twelve digits,
#    leading zero), MAC addresses outside the RFC 7042 documentation block,
#    and values inside the config elements that carry names and secrets.
while IFS= read -r hit; do
  report "possible serial number: $hit"
done < <(grep -HInE '(^|[^0-9])0[0-9]{11}([^0-9]|$)' "${files[@]}" 2>/dev/null)
while IFS= read -r hit; do
  report "MAC address: $hit"
done < <(grep -HInE '(^|[^0-9a-fA-F:])([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}([^0-9a-fA-F:]|$)' "${files[@]}" 2>/dev/null |
         grep -viE '00:00:5e:00:53:|00:00:00:00:00:00|ff:ff:ff:ff:ff:ff')
while IFS= read -r hit; do
  report "config value: $hit"
done < <(grep -HInE '<(hostname|serial|domain|phash|password|private-key|secret|pre-shared-key|key)>[^<[:space:]][^<]*</' "${files[@]}" 2>/dev/null)

# 4. Any e-mail address other than the maintainer's.
while IFS= read -r hit; do
  report "unexpected e-mail address: $hit"
done < <(grep -HInP '(?<![\w.@-])[\w.%+-]+@(?:[a-zA-Z0-9-]*[a-zA-Z][a-zA-Z0-9-]*\.)+[a-zA-Z]{2,}\b' "${files[@]}" 2>/dev/null |
         grep -vE 'thomasbortolossi@gmail\.com|noreply@|@example\.(com|org)|\.anon\.internal')

# 5. Credential material, including PAN-OS encrypted values (-AQ==…) and
#    crypt hashes. The files that carry these patterns are excluded.
scan=()
for f in "${files[@]}"; do
  case $f in tools/check-no-customer-data.sh|plugins/read-tsf/bin/read-tsf-sync*) ;; *) scan+=("$f") ;; esac
done
while IFS= read -r hit; do
  report "possible credential: $hit"
done < <([ ${#scan[@]} -eq 0 ] || grep -HInE 'BEGIN [A-Z ]*PRIVATE KEY|ghp_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN CERTIFICATE-----|-AQ==[A-Za-z0-9+/=]{8,}|\$[156]\$[A-Za-z0-9./]{8,}' "${scan[@]}" 2>/dev/null)

if [ $fail -ne 0 ]; then
  echo
  echo "Refusing: use the placeholders in CLAUDE.md (100.64.x.y, 192.0.2.x, hostNNN, userNNN, ZONE-0012)."
  exit 1
fi
echo "no customer data found in ${#files[@]} tracked files"
