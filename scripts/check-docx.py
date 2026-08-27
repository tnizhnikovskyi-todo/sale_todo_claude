#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Перевіряє, що .docx зібраний у фірмовому стилі ToDo (shared/docx_style.md).

    python3 scripts/check-docx.py файл.docx [файл2.docx ...]

Перевірок девʼять, і кожна відповідає рядку контракту стилю. Скрипт падає з кодом 1
і переліком порушень — його місце в Pre-save верифікації скілів, що віддають
клієнтські документи.

Візуального рендеру в цьому середовищі немає (LibreOffice не завантажує файли),
тому перевірка структурна: шрифт, кеглі, кольори, шапка таблиці, розмітка сторінки,
колонтитули, порожні абзаци. Один раз відкрити результат у Word усе одно варто —
це сказано і в скілах.
"""
import re, sys, zipfile

ARIAL, ORANGE, TBLHEAD = 'Arial', 'ED7D31', 'FE5000'
PGSZ = ('11906', '16838')
MARGINS = dict(top='1276', right='566', bottom='851', left='1418')


def check(path):
    bad = []
    try:
        z = zipfile.ZipFile(path)
    except Exception as e:
        return [f'не читається як .docx: {e}']
    names = z.namelist()
    doc = z.read('word/document.xml').decode('utf-8')

    # 1. усі частини на місці
    for need in ('word/styles.xml', 'word/numbering.xml', 'word/header1.xml',
                 'word/footer1.xml', 'word/theme/theme1.xml'):
        if need not in names:
            bad.append(f'немає частини {need} — шаблон не з assets/docx-template')

    # 2. шрифт: у прогонах тільки Arial (виняток — Consolas для `коду`)
    fonts = set(re.findall(r'<w:rFonts w:ascii="([^"]+)"', doc))
    alien = fonts - {ARIAL, 'Consolas'}
    if alien:
        bad.append(f'сторонні шрифти в прогонах: {sorted(alien)} — має бути Arial')
    if ARIAL not in fonts:
        bad.append('жодного прогону з Arial — шрифт не проставлений')

    # 3. кеглі: 12pt тіло, 13/16pt заголовки, 36pt титул
    szs = {int(s) for s in re.findall(r'<w:sz w:val="(\d+)"', doc)}
    allowed = {2, 12, 20, 22, 24, 26, 32, 72}   # 2 — волосяна лінія, 12 — відбивка
    if szs - allowed:
        bad.append(f'нестандартні кеглі: {sorted(szs - allowed)} (в half-points)')

    # 4. заголовки розділів — оранжеві
    if '<w:pStyle w:val="1"/>' in doc and ORANGE not in doc:
        bad.append(f'є заголовки розділів, але немає кольору {ORANGE}')

    # 5. шапка таблиці — FE5000 з білим текстом
    tables = re.findall(r'<w:tbl>.*?</w:tbl>', doc, re.S)
    for i, t in enumerate(tables, 1):
        rows = re.findall(r'<w:tr\b.*?</w:tr>', t, re.S)
        if not rows:
            bad.append(f'таблиця {i}: без рядків'); continue
        if f'w:fill="{TBLHEAD}"' not in rows[0]:
            bad.append(f'таблиця {i}: шапка без заливки {TBLHEAD}')
        if 'w:val="FFFFFF"' not in rows[0]:
            bad.append(f'таблиця {i}: текст шапки не білий')
        if '<w:tblBorders>' not in t:
            bad.append(f'таблиця {i}: без рамок')
        cols = len(re.findall(r'<w:gridCol', t))
        for ri, r in enumerate(rows, 1):
            n = len(re.findall(r'<w:tc>', r))
            if n != cols:
                bad.append(f'таблиця {i}, рядок {ri}: {n} клітинок при {cols} колонках')

    # 6. розмітка сторінки
    m = re.search(r'<w:pgSz w:w="(\d+)" w:h="(\d+)"/>', doc)
    if not m or (m.group(1), m.group(2)) != PGSZ:
        bad.append('розмір сторінки не A4 як у шаблоні')
    m = re.search(r'<w:pgMar ([^/]+)/>', doc)
    if m:
        got = dict(re.findall(r'w:(\w+)="(\d+)"', m.group(1)))
        for k, v in MARGINS.items():
            if got.get(k) != v:
                bad.append(f'поле сторінки {k}={got.get(k)}, у шаблоні {v}')
    else:
        bad.append('немає w:pgMar')

    # 7. колонтитули підключені
    for kind, rid in (('headerReference w:type="default"', 'rId26'),
                      ('footerReference w:type="default"', 'rId27'),
                      ('headerReference w:type="first"', 'rId28')):
        if f'<w:{kind} r:id="{rid}"/>' not in doc:
            bad.append(f'не підключено: {kind}')
    if '<w:titlePg/>' not in doc:
        bad.append('немає <w:titlePg/> — на першій сторінці буде шапка з логотипом')

    # 8. плейсхолдери не лишились
    for ph in ('⚠️ ІНСТРУКЦІЯ', '__TITLE__', '__DATE__', '[назва компанії]', '[N]'):
        if ph in doc:
            bad.append(f'у документі лишився плейсхолдер: {ph}')

    # 9. службові маркери розмітки не протекли в текст
    texts = ' '.join(re.findall(r'<w:t(?:\s[^>]*)?>(.*?)</w:t>', doc, re.S))
    for leak in ('[[LOGO]]', '[[PAGEBREAK]]', '**', '|---'):
        if leak in texts:
            bad.append(f'розмітка протекла в текст: {leak}')

    return bad


def main():
    if len(sys.argv) < 2:
        raise SystemExit('вжиток: check-docx.py файл.docx [...]')
    fail = 0
    for p in sys.argv[1:]:
        bad = check(p)
        print(f'▸ {p}')
        for b in bad:
            print(f'  ✗ {b}')
        if bad:
            fail = 1
        else:
            print('  ок — стиль фірмовий')
    sys.exit(fail)


if __name__ == '__main__':
    main()
