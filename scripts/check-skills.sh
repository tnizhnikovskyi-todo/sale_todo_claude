#!/usr/bin/env bash
# Перевіряє SKILL.md на конвенції дому (див. CLAUDE.md).
# Скіли без SKILL.md пропускаються — вони ще не написані.
set -uo pipefail
export LC_ALL=C.utf8   # без цього grep працює в байтовому режимі і кириличні діапазони [иу] не збігаються
cd "$(dirname "$0")/.."
. ./scripts/lib-scope.sh

fail=0
found=0

need () { # need <файл> <опис> <grep-патерн>
  grep -qE -- "$3" "$1" || { echo "  ✗ $2"; fail=1; }
}

for f in $(our_skill_files); do
  [ -e "$f" ] || continue
  found=$((found+1))
  dir=$(dirname "$f"); slug=$(basename "$dir")
  echo "▸ $slug"

  # --- frontmatter ---
  # Пастка: `echo "$x" | grep -q` під `set -o pipefail` дає випадкові фальшиві падіння —
  # grep -q виходить на першому збігу, echo отримує SIGPIPE (141), і pipefail віддає 141
  # як статус усього конвеєра. Тому тут і далі — herestring, без конвеєра.
  IFS= read -r first_line < "$f"
  grep -qx -- '---' <<<"$first_line" || { echo "  ✗ немає frontmatter на першому рядку"; fail=1; }

  # тільки frontmatter: від другого рядка до першого закриваючого ---
  fm=$(awk 'NR>1 && /^---$/{exit} NR>1{print}' "$f")
  fm_name=$(sed -n 's/^name: *//p' <<<"$fm" | head -1)
  [ "$fm_name" = "$slug" ] || { echo "  ✗ name: '$fm_name' ≠ каталог '$slug'"; fail=1; }

  grep -q 'Запускай\|Використовуй' <<<"$fm" || { echo "  ✗ description без «Запускай коли…»"; fail=1; }
  grep -q 'Тригерні фрази\|Тригери' <<<"$fm" || { echo "  ✗ description без тригерних фраз"; fail=1; }
  grep -q 'НЕ для\|НЕ розбирає\|НЕ пише\|НЕ протокол\|НЕ лист\|НЕ ' <<<"$fm" || { echo "  ✗ description без негативної межі «НЕ для X»"; fail=1; }
  grep -q 'Результат' <<<"$fm" || { echo "  ✗ description без «Результат — файл»"; fail=1; }

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
  need "$f" 'немає канонічного рядка «Регістр виходу:» / «Регістри виходів:»' '(Регістр|Регістри) вихо'
  need "$f" 'немає правила «Не вигадуй»'        'Не вигадуй'
  grep -q "\`$slug\`" shared/registers.md || { echo "  ✗ скіл не внесений у мапу регістрів shared/registers.md, розділ 1а"; fail=1; }

  # --- прив'язка Pre-save до спільних конвенцій (§2 мова · §3 обсяг · §4 ідемпотентність) ---
  for c in 'Обсяг у межах' 'Мова за' 'Повторний прогін'; do
    grep -qE "^- \[ \] \*\*$c" "$f" || { echo "  ✗ у Pre-save немає рядка «$c …§ конвенцій»"; fail=1; }
  done

  # --- §9 конвенцій: довідники названі розділами, а не файлами ---
  ref_block=$(awk '/^\*\*Довідник/{inb=1;print;next} inb && (/^\*\*/ || /^---$/){exit} inb' "$f")
  if [ -n "$ref_block" ]; then
    grep -q 'розділ' <<<"$ref_block" || { echo "  ✗ блок «Довідники» не називає розділів (§9 конвенцій)"; fail=1; }
  fi

  # --- хто віддає .docx, той складає його скриптами, а не руками ---
  # блок збереження потрібен двом перевіркам нижче
  save_block=$(awk '/^\*\*Збереження результату/{inb=1; next} inb && (/^\*\*/ || /^---$/){exit} inb' "$f")

  # тільки для тих, хто .docx ВІДДАЄ: згадка у «Читанні» не рахується
  if grep -q '\.docx' <<<"$save_block"; then
    grep -q 'make-docx.py' "$f" || { echo "  ✗ віддає .docx, але не викликає scripts/make-docx.py"; fail=1; }
    grep -q 'check-docx.py' "$f" || { echo "  ✗ віддає .docx, але не перевіряє scripts/check-docx.py"; fail=1; }
    grep -q 'check-humizer.py' "$f" || { echo "  ✗ віддає клієнтський .docx, але не прогоняє scripts/check-humizer.py — Humizer лишається лише вичиткою"; fail=1; }
    [ -f "$dir/references/docx_style.md" ] || { echo "  ✗ віддає .docx без контракту стилю в references/ — додай у scripts/shared-map.txt"; fail=1; }
    # інструментарій мусить лежати ВСЕРЕДИНІ скіла: встановлений плагін кореня репозиторію не бачить
    for need in scripts/make-docx.py scripts/check-docx.py scripts/check-humizer.py \
                assets/docx-template/word/styles.xml assets/docx-boilerplate/про-odoo.md; do
      [ -f "$dir/$need" ] || { echo "  ✗ віддає .docx, але в скілі немає $need — перезапусти sync-shared.sh"; fail=1; }
    done
  fi

  # --- хто пише в живу базу, той тримає §10 конвенцій ---
  if grep -q 'odoo_write\|odoo_create' "$f"; then
    grep -q 'fields_get' "$f" || { echo "  ✗ пише в базу, але не згадує fields_get перед записом у selection-поле (§10 конвенцій)"; fail=1; }
    grep -qE '^- \[ \] \*\*Запис у selection-поле' "$f" || { echo "  ✗ пише в базу, але в Pre-save немає рядка «Запис у selection-поле … §10 конвенцій»"; fail=1; }
  fi

  # --- обсяг SKILL.md: 550 рядків ≈ 12k токенів on-invoke (заміряно, §3 конвенцій) ---
  ln=$(wc -l < "$f")
  [ "$ln" -le 550 ] || { echo "  ✗ $ln рядків — понад 550 (≈12k токенів за прогін). Спершу шукай дублювання з контрактом"; fail=1; }

  # --- плейсхолдери шаблону ---
  grep -q '⚠️ ІНСТРУКЦІЯ' "$f" || { echo "  ✗ у шаблоні немає плейсхолдерів [⚠️ ІНСТРУКЦІЯ: …]"; fail=1; }

  # --- клієнтський регістр → Humizer блокуючий ---
  if grep -q 'Регістр виходу: 3\|Регістр: клієнтський\|регістр 3 — клієнтський\|3 — клієнтський' "$f"; then
    grep -qE '^- \[ \] .*Humizer пройдено' "$f" || { echo "  ✗ клієнтський регістр без рядка чеклісту «- [ ] Humizer пройдено»"; fail=1; }
  fi

  # --- writer журналу → інваріанти ID ---
  # Writer визначається структурно: у блоці «Збереження результату» журнал іде у Write.
  # Раніше тут стояла додаткова умова «у тексті є слова writer журналу» — під неї
  # підпадав один скіл із шести, тобто перевірка була майже порожньою.
  # save_block обчислений вище. Sed-діапазон тут не годиться: без закриваючого
  # рядка він тягне файл до кінця, і writer'ом виглядає кожен скіл, що згадує журнал
  if grep -q 'журнал_продажу' <<<"$save_block" && grep -q 'Write' <<<"$save_block"; then
    need "$f" 'writer журналу без «продовжуй ID, не перенумеровуй»' 'Продовжуй ID|продовжуй нумерацію|продовжують нумерацію|продовжуй ID|нічого не перенумеровуй|не перенумеровуй'
    need "$f" 'writer журналу без «оновлюй на місці»' 'на місці'
  fi

  # --- машиночитний регістр не оголошує Humizer як пройдений ---
  if grep -q 'Humizer заборонений' "$f" && grep -q 'Humizer пройдено' "$f"; then
    grep -q 'Humizer \*\*не\*\* застосований' "$f" || echo "  ℹ у скілі є і «Humizer заборонений», і «Humizer пройдено» — перевір, що це різні виходи"
  fi
done

# --- довідник прикладів обовʼязковий ---
echo "▸ довідники прикладів"
stubs=0
for f in $(our_skill_files); do
  [ -e "$f" ] || continue
  d=$(dirname "$f"); slug=$(basename "$d")
  if [ ! -f "$d/references/examples.md" ]; then
    echo "  ✗ $slug: немає references/examples.md — додай shared/examples/$slug.md"; fail=1
  elif ! grep -q 'Анонімізація перевірена' "$d/references/examples.md"; then
    echo "  ✗ $slug: у довіднику прикладів немає рядка «Анонімізація перевірена» — додай у shared/examples/$slug.md"; fail=1
  elif grep -q 'ЗАГОТОВКА' "$d/references/examples.md"; then
    stubs=$((stubs+1))
  fi
done
[ "$stubs" -gt 0 ] && echo "  ℹ заготовок без реального прогону: $stubs з 18 — заповнити після прогону"

# --- хто читає журнал, мусить мати його контракт ---
echo "▸ контракт журналу в тих, хто журнал читає"
for f in $(our_skill_files); do
  [ -e "$f" ] || continue
  d=$(dirname "$f"); slug=$(basename "$d")
  reads_block=$(sed -n '/\*\*Читання вх/,/^\*\*[^Ч]/p' "$f")
  if grep -q 'журнал_продажу' <<<"$reads_block"; then
    [ -f "$d/references/deal_journal_template.md" ] || { echo "  ✗ $slug читає журнал, але contract у references/ немає — додай у scripts/shared-map.txt"; fail=1; }
  fi
done

# --- формула коефіцієнта мусить бути дослівною копією контракту ---
echo "▸ формула коефіцієнта"
PLUGDIR="$PLUGDIR" python3 - <<'PYCHK' || fail=1
import os, re, sys
c = open('shared/deal_journal_template.md', encoding='utf-8').read()
d = open(os.path.join(os.environ.get('PLUGDIR', 'plugins'),
                      'odoo19-sales-prep/skills/data-completeness-scorer/SKILL.md'),
         encoding='utf-8').read()
g = lambda t: re.search(r'```\n(\u0454 \u0445\u043e\u0447 \u043e\u0434\u043d\u0435.*?)\n```', t, re.S)
a, b = g(c), g(d)
if not a or not b:
    print('  \u2717 \u043d\u0435 \u0437\u043d\u0430\u0439\u0448\u043e\u0432 \u0444\u043e\u0440\u043c\u0443\u043b\u0443'); sys.exit(1)
if a.group(1) != b.group(1):
    print('  \u2717 \u0444\u043e\u0440\u043c\u0443\u043b\u0430 \u0432 data-completeness-scorer \u0440\u043e\u0437\u0456\u0448\u043b\u0430\u0441\u044c \u0456\u0437 \u043a\u043e\u043d\u0442\u0440\u0430\u043a\u0442\u043e\u043c'); sys.exit(1)
PYCHK

# --- перехресні посилання: чи існує кожен згаданий скіл ---
OURS=$(our_skill_files | xargs -n1 dirname 2>/dev/null | xargs -n1 basename 2>/dev/null | sort -u)
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
PLUGINS=$(ours; echo "odoo19-discovery-initiation
odoo19-discovery-sessions odoo19-discovery-closeout odoo19-tr-authoring odoo19-mvp-build
odoo19-implementation odoo-connector")
KNOWN=$(printf '%s\n%s\n%s\n' "$OURS" "$HOUSE" "$PLUGINS" | tr ' ' '\n' | sed '/^$/d' | sort -u)

echo "▸ стик із треком упровадження"
# дев'ять блоків контракту передачі мусять бути в скілі досьє — дослівно.
# Розійдуться тихо: обидва файли лишаться валідними, а споживач не знайде блоку.
d="$PLUGDIR/odoo19-sales-offer/skills/handover-dossier-builder/SKILL.md"
n=0
while IFS='|' read -r _ num name _; do
  name=$(echo "$name" | sed 's/^ *//; s/ *$//; s/\*\*//g')
  [ -n "$name" ] || continue
  n=$((n+1))
  grep -qF "$name" "$d" || { echo "  ✗ блок «$name» є в handover_contract.md, але не в скілі досьє"; fail=1; }
done < <(awk '/^\| # \| Блок \|/{f=1;next} f&&/^\|---/{next} f&&/^\|/{print} f&&!/^\|/{exit}' shared/handover_contract.md)
if [ "$n" -ne 9 ]; then
  echo "  ✗ у handover_contract.md розібрано $n блоків, а має бути 9 — таблиця з'їхала"; fail=1
else
  echo "  блоків стику звірено: $n"
fi

echo "▸ тригерні фрази ланцюга"
python3 scripts/check-triggers.py || fail=1

echo "▸ перехресні посилання"
for f in $(our_skill_files); do
  [ -e "$f" ] || continue
  for r in $(grep -oE '`[a-z][a-z0-9]+(-[a-z0-9]+){1,4}`' "$f" | tr -d '`' | sort -u); do
    case "$r" in *.md|*.json|*.sh|*.ltd|*.com|*.ua) continue ;; esac
    grep -qx "$r" <<<"$KNOWN" || { echo "  ✗ $(basename "$(dirname "$f")") посилається на невідомий скіл: $r"; fail=1; }
  done
done

echo
if [ "$found" -eq 0 ]; then echo "SKILL.md не знайдено"; exit 0; fi
echo "Перевірено скілів: $found"
[ "$fail" -eq 0 ] && echo "OK — конвенції дотримані" || { echo "Є порушення конвенцій" >&2; exit 1; }
