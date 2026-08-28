#!/usr/bin/env bash
# Прогоняє конвейєр .docx на чотирьох чернетках-фікстурах і на негативних кейсах.
# Позитив: чотири клієнтські документи збираються і проходять перевірку стилю.
# Негатив: непідтримувана розмітка падає з номером рядка, а не тихо ковтається.
set -uo pipefail
export LC_ALL=C.utf8
cd "$(dirname "$0")/.."

out=$(mktemp -d); trap 'rm -rf "$out"' EXIT
fail=0

echo "▸ позитив: чотири документи"
for src in tests/docx/*.md; do
  name=$(basename "$src" .md)
  if ! python3 scripts/make-docx.py "$src" "$out/$name.docx" --title "$name" >/dev/null 2>"$out/err"; then
    echo "  ✗ $name: складання впало — $(tail -1 "$out/err")"; fail=1; continue
  fi
  if ! python3 scripts/check-docx.py "$out/$name.docx" >"$out/chk" 2>&1; then
    echo "  ✗ $name: стиль"; sed 's/^/      /' "$out/chk"; fail=1; continue
  fi
  paras=$(python3 - "$out/$name.docx" <<'PY'
import sys, zipfile, re
d = zipfile.ZipFile(sys.argv[1]).read('word/document.xml').decode('utf-8')
print(len(re.findall(r'<w:p[ >]', d)), 'абзаців ·',
      len(re.findall(r'<w:tbl>', d)), 'табл ·',
      len(re.findall(r'w:numId w:val="900"', d)), 'марк')
PY
)
  echo "  ✓ $name: $paras"
done

echo "▸ позитив: анкета зі шаблону"
# перевіряємо сам шаблон, а не його копію — інакше він тихо розійдеться з тестом
python3 - "$out/анкета.md" <<'PY'
import sys, re
src = open('assets/questionnaire/анкета.md', encoding='utf-8').read()
src = re.sub(r'\[⚠️ ІНСТРУКЦІЯ: назва компанії клієнта\]', 'ЗРАЗОК', src)
src = re.sub(r'\[⚠️ ІНСТРУКЦІЯ: РРРР-ММ-ДД\]', '2026-08-27', src)
open(sys.argv[1], 'w', encoding='utf-8').write(src)
PY
if python3 scripts/make-docx.py "$out/анкета.md" "$out/анкета.docx" --title Анкета >/dev/null 2>"$out/err" \
   && python3 scripts/check-docx.py "$out/анкета.docx" >/dev/null 2>&1; then
  forms=$(python3 - "$out/анкета.docx" <<'PY'
import sys, zipfile, re
d = zipfile.ZipFile(sys.argv[1]).read('word/document.xml').decode('utf-8')
print(len(re.findall(r'<w:tbl>', d)), 'табл ·',
      len(re.findall(r'<w:p[ >]', d)), 'абзаців')
PY
)
  echo "  ✓ анкета: $forms"
else
  echo "  ✗ анкета не збирається або не проходить стиль: $(tail -1 "$out/err")"; fail=1
fi

echo "▸ негатив: розмітка, якої немає"
neg () { # neg <опис> <рядок чернетки>
  printf '# Т\n\n%s\n' "$2" > "$out/n.md"
  msg=$(python3 scripts/make-docx.py "$out/n.md" "$out/n.docx" 2>&1 | tail -1)
  case "$msg" in
    *.docx*) echo "  ✗ НЕ ЛОВИТЬ: $1"; fail=1 ;;
    *)       echo "  ✓ $1" ;;
  esac
}
neg 'таблиця без роздільника' '| a | b |
| c | d |'
neg 'заголовок шостого рівня'  '###### глибше нікуди'
neg 'зображення'               '![схема](x.png)'
neg 'markdown-посилання'       '[сайт](https://todo.ltd)'
neg 'невідома директива'       '[[FOO]]'
neg 'INCLUDE поза репозиторієм' '[[INCLUDE:../../etc/passwd]]'
neg 'INCLUDE неіснуючого'      '[[INCLUDE:assets/docx-boilerplate/немає.md]]'

echo "▸ позитив: те, що раніше ламалось"
pos () { # pos <опис> <фрагмент чернетки> <що мусить бути в тексті> <чого не мусить>
  printf '# Т\n\n%s\n' "$2" > "$out/p.md"
  if ! python3 scripts/make-docx.py "$out/p.md" "$out/p.docx" >/dev/null 2>&1; then
    echo "  ✗ $1: складання впало"; fail=1; return
  fi
  got=$(python3 - "$out/p.docx" <<'PY'
import sys, zipfile, re, html
d = zipfile.ZipFile(sys.argv[1]).read('word/document.xml').decode('utf-8')
print(' '.join(html.unescape(m) for m in re.findall(r'<w:t(?:\s[^>]*)?>(.*?)</w:t>', d, re.S)))
PY
)
  case "$got" in
    *"$4"*) echo "  ✗ $1: у тексті лишилось «$4»"; fail=1 ;;
    *"$3"*) echo "  ✓ $1" ;;
    *)      echo "  ✗ $1: у тексті немає «$3»"; fail=1 ;;
  esac
}
pos 'жирний через розрив рядка' 'Для кожного кроку: **хто робить**
і **де працює**.' 'хто робить' '**'
pos 'порожня таблиця-форма' '| Крок | Хто |
|---|---|
| | |' 'Крок' '|---|'

echo "▸ негатив: зламаний стиль ловиться перевіркою"
python3 scripts/make-docx.py tests/docx/КП.md "$out/kp.docx" --title КП >/dev/null
brk () { # brk <опис> <що замінити> <на що>
  python3 - "$out/kp.docx" "$out/broken.docx" "$2" "$3" <<'PY'
import sys, zipfile
src, dst, a, b = sys.argv[1:5]
zi = zipfile.ZipFile(src)
with zipfile.ZipFile(dst, 'w', zipfile.ZIP_DEFLATED) as zo:
    for it in zi.infolist():
        d = zi.read(it.filename)
        if it.filename == 'word/document.xml':
            d = d.decode('utf-8').replace(a, b).encode('utf-8')
        zo.writestr(it, d)
PY
  if python3 scripts/check-docx.py "$out/broken.docx" >/dev/null 2>&1; then
    echo "  ✗ НЕ ЛОВИТЬ: $1"; fail=1
  else
    echo "  ✓ $1"
  fi
}
brk 'сторонній шрифт'      'w:ascii="Arial"'        'w:ascii="Times New Roman"'
brk 'шапка таблиці без заливки' 'w:fill="FE5000"'   'w:fill="FFFFFF"'
brk 'поля сторінки'        'w:left="1418"'          'w:left="1000"'
brk 'колонтитул відпав'    '<w:footerReference w:type="default" r:id="rId27"/>' ''
brk 'титульна сторінка'    '<w:titlePg/>'           ''
brk 'залишений плейсхолдер' 'Шановні партнери'      '[⚠️ ІНСТРУКЦІЯ: звернення] Шановні партнери'
brk 'протік розмітки'      'Дякуємо за довіру'      '[[LOGO]] Дякуємо за довіру'

echo "▸ Humizer: клієнтські документи без внутрішніх слідів"
if python3 scripts/check-humizer.py tests/docx/*.md assets/questionnaire/анкета.md \
     assets/docx-boilerplate/*.md >"$out/hz" 2>&1; then
  echo "  ✓ фікстури, анкета і стабільні блоки чисті"
else
  echo "  ✗ у фікстурах є внутрішні сліди"; grep '✗' "$out/hz" | sed 's/^/      /'; fail=1
fi

hz () { # hz <опис> <рядок, який мусить впасти>
  printf '# Т\n\n%s\n' "$2" > "$out/hz.md"
  if python3 scripts/check-humizer.py "$out/hz.md" >/dev/null 2>&1; then
    echo "  ✗ НЕ ЛОВИТЬ: $1"; fail=1
  else
    echo "  ✓ $1"
  fi
}
hz 'ID реєстру'        'Покривається налаштуванням, див. G-12.'
hz 'тег пріоритету'    'Питання [КО] лишається відкритим.'
hz 'маркер рівня'      'Ризик 🔴 високий.'
hz 'слід транскрипту'  'Speaker 2 зазначив, що потрібен облік.'
hz 'коефіцієнт'        'Вилка порахована з коефіцієнтом повноти даних.'
hz 'ставка за годину'  'Вартість залежить від ставки впровадження.'
hz 'множник вилки'     'Верхня межа ×3 через неповноту даних.'
hz 'жаргон'            'Уточнимо scope і перенесемо master data.'
hz 'канцелярит'        'Списання здійснюється автоматично.'
hz 'посилання Fathom'  'Запис зустрічі: https://fathom.video/share/abc123'
hz 'блок питань §13'   'Без відповіді: рахую за базовою ставкою.'
# мітки реплік: ловиться діалог, а не одна назва з двокрапкою (див. SPEAKER_UA)
hz 'дві мітки реплік'  'Мазуренко Ігор: перевіримо. Козиревський Іван: добре.'
hz 'мітка повторилась' 'Мазуренко Ігор: перевіримо. Далі. Мазуренко Ігор: ще раз.'

hzp () { # hzp <опис> <рядок, який ловитись НЕ мусить>
  printf '# Т\n\n%s\n' "$2" > "$out/hz.md"
  if python3 scripts/check-humizer.py "$out/hz.md" >/dev/null 2>&1; then
    echo "  ✓ не хибує: $1"
  else
    echo "  ✗ ХИБНЕ СПРАЦЮВАННЯ: $1"; fail=1
  fi
}
hzp 'версія документа'  'Версія 2 від 27.08.2026. Замінює версію 1.'
hzp 'дата з дефісом'    'Термін — 3-4 тижні від старту.'
hzp 'ціна ліцензії'     'Ліцензія коштує 22,40 € за користувача на місяць.'
hzp 'ставка податку'    'Ставка податку підставляється за локалізацією.'
hzp 'формат A4'         'Документ формату A4, стандарт ISO 216.'
hzp 'назва з двокрапкою' 'Нова Пошта: обмін накладними за API.'
hzp 'посада з двокрапкою' 'Відповідальний з боку Замовника: керівник проєкту.'

echo
[ "$fail" -eq 0 ] && echo "OK — конвейєр .docx тримається" || { echo "Є порушення" >&2; exit 1; }
