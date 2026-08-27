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

# --- довідники прикладів: shared/examples/<slug>.md → <skill>/references/examples.md ---
# за конвенцією, без мапи: імʼя файлу = імʼя скіла
e=0
for src in shared/examples/*.md; do
  slug=$(basename "$src" .md)
  # без `ls | head`: під pipefail головна команда конвеєра ловить SIGPIPE і падає
  d=""
  for cand in plugins/*/skills/"$slug"; do [ -d "$cand" ] && { d="$cand"; break; }; done
  [ -n "$d" ] || { echo "НЕМАЄ скіла для приклада $slug" >&2; exit 1; }
  mkdir -p "$d/references"
  {
    echo "<!-- ЗГЕНЕРОВАНО з $src скриптом scripts/sync-shared.sh."
    echo "     Не правити тут — правки затираються. Канонічне джерело: $src -->"
    echo
    cat "$src"
  } > "$d/references/examples.md"
  e=$((e+1))
done

echo "Розкладено копій: $n · довідників прикладів: $e"
