#!/usr/bin/env bash
# Перевірка пакування: маркетплейс справді ставиться, і плагіни несуть свої скіли.
#
#     ./scripts/verify-install.sh [git-ref]        (типово HEAD)
#
# Навіщо окремий скрипт. `claude plugin validate` перевіряє манифести, а не установку:
# заміряно, що установка вміє написати «√ Successfully installed» і дати НУЛЬ скілів.
# Єдиний спосіб це побачити — поставити з клону і прочитати `plugin details`.
#
# **Кеш ізольований.** `claude plugin marketplace remove` кеш НЕ чистить, тому
# повторний прогін у тому самому контейнері читає стару версію і рапортує зеленим.
# Щоб не залежати від чистоти справжнього кеша й не чистити його руками, скрипт
# піднімає власний HOME у тимчасовому каталозі. Справжній ~/.claude не торкається.
set -uo pipefail
export LC_ALL=C.utf8
cd "$(dirname "$0")/.."
. ./scripts/lib-scope.sh

command -v claude >/dev/null 2>&1 || {
  echo "▸ перевірка установки — CLI Claude Code недоступний, пропущено"; exit 0; }

ref="${1:-HEAD}"
mkt=$(python3 -c "import json;print(json.load(open('.claude-plugin/marketplace.json'))['name'])")
ver=$(python3 -c "import json;print(json.load(open('.claude-plugin/marketplace.json'))['version'])")
src=$(pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fail=0

echo "▸ клон $ref у чистий каталог"
git clone -q "$src" "$tmp/clone" && git -C "$tmp/clone" checkout -q "$ref" || {
  echo "  ✗ не вдалось склонувати $ref"; exit 1; }
echo "  $(git -C "$tmp/clone" log --oneline -1)"

export HOME="$tmp/home"; mkdir -p "$HOME"
echo "▸ маркетплейс $mkt із клону (кеш у $HOME/.claude)"
claude plugin marketplace add "$tmp/clone" >/dev/null 2>&1 || {
  echo "  ✗ marketplace add не пройшов"; exit 1; }

echo "▸ установка і скіли"
for p in $(ours); do
  want=$(ls -d "$PLUGDIR/$p"/skills/*/ 2>/dev/null | wc -l)
  claude plugin install "$p@$mkt" >/dev/null 2>&1
  got=$(claude plugin details "$p@$mkt" 2>&1 | grep -oE 'Skills \([0-9]+\)' | head -1 | tr -dc '0-9')
  if [ "${got:-0}" -eq 0 ]; then
    echo "  ✗ $p: Skills (0) — установка «пройшла», а скілів немає. Це провал пакування"; fail=1
  elif [ "${got:-0}" -ne "$want" ]; then
    echo "  ✗ $p: у кеші $got скілів, у дереві $want"; fail=1
  else
    echo "  ✓ $p: $got скілів"
  fi
done

echo "▸ інструментарій у кеші = інструментарій у коміті"
for p in $(ours); do
  for d in $(find "$HOME/.claude/plugins/cache/$mkt/$p" -type d -name scripts 2>/dev/null); do
    skill=$(basename "$(dirname "$d")")
    if diff -rq "$d" "$PLUGDIR/$p/skills/$skill/scripts" >/dev/null 2>&1; then
      echo "  ✓ $p/$skill"
    else
      echo "  ✗ $p/$skill: у кеші не те, що в коміті"; fail=1
    fi
  done
done

echo "▸ конвейєр .docx із каталогу встановленого скіла"
mk=$(find "$HOME/.claude/plugins/cache/$mkt" -path '*presale-pack-builder/scripts/make-docx.py' | head -1)
if [ -z "$mk" ]; then
  echo "  ✗ у кеші немає make-docx.py — інструментарій не поїхав із скілом"; fail=1
else
  d=$(dirname "$(dirname "$mk")")
  # анкету спершу заповнюємо: плейсхолдери-інструкції check-docx.py ловить за призначенням
  sed -e 's/\[⚠️ ІНСТРУКЦІЯ: назва компанії клієнта\]/ЗРАЗОК/' \
      -e 's/\[⚠️ ІНСТРУКЦІЯ: РРРР-ММ-ДД\]/2026-01-01/' \
      "$d/assets/questionnaire/анкета.md" > "$tmp/a.md"
  if python3 "$d/scripts/make-docx.py" "$tmp/a.md" "$tmp/a.docx" --title Анкета >/dev/null 2>&1 \
     && python3 "$d/scripts/check-docx.py" "$tmp/a.docx" >/dev/null 2>&1 \
     && python3 "$d/scripts/check-humizer.py" "$tmp/a.docx" >/dev/null 2>&1; then
    echo "  ✓ зібрався і пройшов стиль та Humizer — без доступу до кореня репозиторію"
  else
    echo "  ✗ конвейєр із каталогу скіла не працює"; fail=1
  fi
fi

echo "▸ ціна контексту (always-on)"
tot=0
for p in $(ours); do
  n=$(claude plugin details "$p@$mkt" 2>&1 | grep -oE 'Always-on: +~[0-9,]+' | tr -dc '0-9')
  printf '  %-22s ~%s\n' "$p" "${n:-?}"; tot=$((tot + ${n:-0}))
done
echo "  разом: ≈$tot токенів у кожній сесії"

for p in $(ours); do claude plugin uninstall "$p@$mkt" >/dev/null 2>&1; done
claude plugin marketplace remove "$mkt" >/dev/null 2>&1

echo
[ "$fail" -eq 0 ] && echo "OK — версія $ver ставиться і несе скіли" \
                  || { echo "Є порушення пакування" >&2; exit 1; }
