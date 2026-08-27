#!/usr/bin/env bash
# Розкладає канонічні контракти з shared/ у references/ кожного скіла за scripts/shared-map.txt.
set -euo pipefail
export LC_ALL=C.utf8   # без цього grep працює в байтовому режимі і кириличні діапазони [иу] не збігаються
cd "$(dirname "$0")/.."

n=0
while read -r src dests; do
  [ -z "${src:-}" ] && continue
  case "$src" in \#*) continue ;; esac
  [ -f "shared/$src" ] || { echo "НЕМАЄ shared/$src" >&2; exit 1; }
  for d in $dests; do
    [ -d "$d" ] || { echo "НЕМАЄ каталогу скіла $d" >&2; exit 1; }
    mkdir -p "$d/references"
    {
      echo "<!-- ЗГЕНЕРОВАНО з shared/$src скриптом scripts/sync-shared.sh."
      echo "     Не правити тут — правки затираються. Канонічне джерело: shared/$src -->"
      echo
      cat "shared/$src"
    } > "$d/references/$src"
    n=$((n+1))
  done
done < <(sed -e ':a' -e '/\\$/{N;s/\\\n//;ba' -e '}' scripts/shared-map.txt)

echo "Розкладено копій: $n"
