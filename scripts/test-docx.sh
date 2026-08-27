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

echo
[ "$fail" -eq 0 ] && echo "OK — конвейєр .docx тримається" || { echo "Є порушення" >&2; exit 1; }
