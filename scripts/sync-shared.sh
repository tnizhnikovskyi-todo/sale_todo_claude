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

# --- інструментарій .docx у скіли, що віддають клієнтські документи ---
# Скіл, установлений як плагін, не бачить корінь репозиторію: у house-скілах
# інструменти лежать усередині скіла, і в нас так само. Шляхи всередині скіла
# ті самі, що в корені, тому make-docx.py знаходить шаблон відносно себе.
t=0
docx_dests=$(sed -e ':a' -e '/\\$/{N;s/\\\n//;ba' -e '}' scripts/shared-map.txt \
             | awk '$1=="docx_style.md"{for(i=2;i<=NF;i++)print $i}')
for d in $docx_dests; do
  [ -d "$d" ] || { echo "НЕМАЄ каталогу скіла $d" >&2; exit 1; }
  mkdir -p "$d/scripts" "$d/assets"
  for f in make-docx.py check-docx.py; do
    {
      echo "#!/usr/bin/env python3"
      echo "# ЗГЕНЕРОВАНО з scripts/$f скриптом scripts/sync-shared.sh."
      echo "# Не правити тут — правки затираються. Канонічне джерело: scripts/$f"
      tail -n +2 "scripts/$f"
    } > "$d/scripts/$f"
    chmod +x "$d/scripts/$f"
    t=$((t+1))
  done
  rm -rf "$d/assets/docx-template" "$d/assets/docx-boilerplate"
  cp -a assets/docx-template "$d/assets/docx-template"
  cp -a assets/docx-boilerplate "$d/assets/docx-boilerplate"
  t=$((t+2))
done

echo "Розкладено копій: $n · довідників прикладів: $e · інструментарію .docx: $t"
