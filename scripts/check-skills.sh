#!/usr/bin/env bash
# Перевіряє SKILL.md на конвенції дому (див. CLAUDE.md).
# Скіли без SKILL.md пропускаються — вони ще не написані.
set -uo pipefail
cd "$(dirname "$0")/.."

fail=0
found=0

need () { # need <файл> <опис> <grep-патерн>
  grep -qE -- "$3" "$1" || { echo "  ✗ $2"; fail=1; }
}

for f in plugins/*/skills/*/SKILL.md; do
  [ -e "$f" ] || continue
  found=$((found+1))
  dir=$(dirname "$f"); slug=$(basename "$dir")
  echo "▸ $slug"

  # --- frontmatter ---
  head -1 "$f" | grep -qx -- '---' || { echo "  ✗ немає frontmatter на першому рядку"; fail=1; }
  fm_name=$(sed -n '2,20p' "$f" | sed -n 's/^name: *//p' | head -1)
  [ "$fm_name" = "$slug" ] || { echo "  ✗ name: '$fm_name' ≠ каталог '$slug'"; fail=1; }

  fm=$(sed -n '/^---$/,/^---$/p' "$f")
  echo "$fm" | grep -q 'Запускай\|Використовуй' || { echo "  ✗ description без «Запускай коли…»"; fail=1; }
  echo "$fm" | grep -q 'Тригерні фрази\|Тригери' || { echo "  ✗ description без тригерних фраз"; fail=1; }
  echo "$fm" | grep -q 'НЕ для\|НЕ розбирає\|НЕ пише\|НЕ протокол\|НЕ лист\|НЕ ' || { echo "  ✗ description без негативної межі «НЕ для X»"; fail=1; }
  echo "$fm" | grep -q 'Результат' || { echo "  ✗ description без «Результат — файл»"; fail=1; }

  # --- обов'язкові розділи ---
  need "$f" 'немає ## Мета'                    '^## Мета'
  need "$f" 'немає ## Інструменти та середовище' '^## Інструменти та середовище'
  need "$f" 'немає ## Місце в потоці'          '^## Місце (в потоці|в циклі)'
  need "$f" 'немає Крок 0 «визнач вхідні дані»' '^## Крок 0'
  need "$f" 'немає Pre-save верифікації'        'Pre-save верифікація'
  need "$f" 'немає шаблону'                     '^(## Крок [0-9]+: )?Шаблон|^## Шаблон'
  need "$f" 'немає ## Наступний крок'          '^## Наступний крок'
  need "$f" 'немає ## Важливі правила'         '^## Важливі правила'

  # --- обмеження ---
  need "$f" 'регістр виходу не оголошений'      '[Рр]егістр'
  need "$f" 'немає правила «Не вигадуй»'        'Не вигадуй'

  # --- плейсхолдери шаблону ---
  grep -q '⚠️ ІНСТРУКЦІЯ' "$f" || { echo "  ✗ у шаблоні немає плейсхолдерів [⚠️ ІНСТРУКЦІЯ: …]"; fail=1; }

  # --- клієнтський регістр → Humizer блокуючий ---
  if grep -q 'Регістр виходу: 3\|Регістр: клієнтський\|регістр 3 — клієнтський\|3 — клієнтський' "$f"; then
    grep -qE '^- \[ \] .*Humizer пройдено' "$f" || { echo "  ✗ клієнтський регістр без рядка чеклісту «- [ ] Humizer пройдено»"; fail=1; }
  fi

  # --- writer журналу → інваріанти ID ---
  if grep -qi 'журнал_продажу_\[.*\]\.md. → .Write\|→ `Write`' "$f" && grep -q 'журнал_продажу' "$f"; then
    if grep -q 'Write' "$f" && grep -qi 'writer журналу' "$f"; then
      need "$f" 'writer журналу без «Продовжуй ID»' 'Продовжуй ID|продовжують нумерацію'
      need "$f" 'writer журналу без «оновлюй на місці»' 'на місці'
    fi
  fi

  # --- машиночитний регістр не оголошує Humizer як пройдений ---
  if grep -q 'Humizer заборонений' "$f" && grep -q 'Humizer пройдено' "$f"; then
    grep -q 'Humizer \*\*не\*\* застосований' "$f" || echo "  ℹ у скілі є і «Humizer заборонений», і «Humizer пройдено» — перевір, що це різні виходи"
  fi
done

# --- перехресні посилання: чи існує кожен згаданий скіл ---
OURS=$(ls -d plugins/*/skills/*/ 2>/dev/null | xargs -n1 basename 2>/dev/null | sort -u)
HOUSE="sales-handover-analyzer session-transcript-analyzer meeting-protocol-builder
kickoff-transcript-analyzer kickoff-survey-protocol odoo-spec-writer tr-usecases-acceptance
tr-odoo-tech-design tr-effort-instruction tr-review tr-registry-update tr-change-request
discovery-scope-mapper session-question-builder session-client-prep-builder
client-web-researcher competitor-mapper industry-briefing discovery-context-builder
kickoff-agenda-finalizer kickoff-question-builder facilitation-guide-builder
discovery-charter-writer discovery-plan-builder build-allocator config-spec config-runbook
config-review data-migration-planner go-live-runbook user-training-builder hypercare-tracker
acceptance-act-builder odoo-architecture scaffolding code-dev testing pr-review
security-review skill-creator"
# назви плагінів — не скіли, посилання на них легітимні
PLUGINS=$(ls -d plugins/*/ 2>/dev/null | xargs -n1 basename 2>/dev/null; echo "odoo19-discovery-initiation
odoo19-discovery-sessions odoo19-discovery-closeout odoo19-tr-authoring odoo19-mvp-build
odoo19-implementation odoo-connector")
KNOWN=$(printf '%s\n%s\n%s\n' "$OURS" "$HOUSE" "$PLUGINS" | tr ' ' '\n' | sed '/^$/d' | sort -u)

echo "▸ перехресні посилання"
for f in plugins/*/skills/*/SKILL.md; do
  [ -e "$f" ] || continue
  for r in $(grep -oE '`[a-z][a-z0-9]+(-[a-z0-9]+){1,4}`' "$f" | tr -d '`' | sort -u); do
    case "$r" in *.md|*.json|*.sh|*.ltd|*.com|*.ua) continue ;; esac
    echo "$KNOWN" | grep -qx "$r" || { echo "  ✗ $(basename "$(dirname "$f")") посилається на невідомий скіл: $r"; fail=1; }
  done
done

echo
if [ "$found" -eq 0 ]; then echo "SKILL.md не знайдено"; exit 0; fi
echo "Перевірено скілів: $found"
[ "$fail" -eq 0 ] && echo "OK — конвенції дотримані" || { echo "Є порушення конвенцій" >&2; exit 1; }
