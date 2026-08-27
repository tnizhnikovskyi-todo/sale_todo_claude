#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Складає .docx у фірмовому стилі ToDo з розмітки-підмножини Markdown.

Стиль знятий із реального КП компанії (див. shared/docx_style.md) і зашитий тут:
Arial, заголовки розділів оранжеві, шапка таблиці FE5000 білим, шапка сторінки
з логотипом і адресою, нумерація сторінок у колонтитулі.

    python3 scripts/make-docx.py вхід.md вихід.docx [--title "Назва документа"]

Підтримувана розмітка — рівно те, що потрібно чотирьом клієнтським документам:

    # Титул                     титульний рядок, Arial bold 36, центр
    ## 1. Розділ                 заголовок розділу, оранжевий, центр
    ### Підрозділ                підзаголовок, оранжевий
    #### Блок                    заголовок 3-го рівня, чорний жирний
    ##### Дрібніший блок         заголовок 4-го рівня, чорний курсив
    текст                        абзац
    - пункт                      маркований список (вкладеність — два пробіли)
    1. пункт                     нумерований список
    | a | b |                    таблиця; другий рядок-роздільник обов'язковий
    > текст                      виноска на сірому тлі з оранжевою лінією
    ---                          тонка лінія
    [[PAGEBREAK]]                розрив сторінки
    [[LOGO]]                     логотип ToDo, центр
    [[INCLUDE:шлях.md]]          вставити файл дослівно (стабільні блоки КП
                                 з assets/docx-boilerplate/)
    **жирний** *курсив*          усередині абзацу, пункту або клітинки

Усе інше — помилка: скрипт падає з номером рядка, а не тихо ковтає розмітку.
"""
import argparse, html, os, re, shutil, struct, sys, tempfile, zipfile
from datetime import datetime, timezone

TPL = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'assets', 'docx-template')

# --- фірмові константи (shared/docx_style.md) ---
ARIAL   = '<w:rFonts w:ascii="Arial" w:eastAsia="Arial" w:hAnsi="Arial" w:cs="Arial"/>'
ORANGE  = 'ED7D31'   # заголовки розділів
TBLHEAD = 'FE5000'   # шапка таблиці
CALLOUT = 'F2F2F2'   # тло виноски
SZ_BODY, SZ_TITLE, SZ_H1, SZ_H2, SZ_H3 = 24, 72, 32, 26, 24
TBL_W   = 9776       # ширина таблиці в dxa, як у зразку
NUM_BUL, NUM_DEC = 900, 901

NS = ('xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
      'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
      'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
      'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"')

SECT = ('<w:sectPr><w:headerReference w:type="default" r:id="rId26"/>'
        '<w:footerReference w:type="default" r:id="rId27"/>'
        '<w:headerReference w:type="first" r:id="rId28"/>'
        '<w:pgSz w:w="11906" w:h="16838"/>'
        '<w:pgMar w:top="1276" w:right="566" w:bottom="851" w:left="1418" '
        'w:header="283" w:footer="172" w:gutter="0"/>'
        '<w:pgNumType w:start="1"/><w:cols w:space="720"/><w:titlePg/></w:sectPr>')


def esc(t):
    return html.escape(t, quote=False).replace('"', '&quot;')


def rpr(*, bold=False, italic=False, mono=False, color=None, sz=SZ_BODY):
    """Порядок дочірніх елементів w:rPr фіксований схемою: rFonts, b, i, color, sz."""
    font = ('<w:rFonts w:ascii="Consolas" w:eastAsia="Consolas" w:hAnsi="Consolas" '
            'w:cs="Consolas"/>') if mono else ARIAL
    out = font
    if bold:   out += '<w:b/>'
    if italic: out += '<w:i/>'
    if color:  out += f'<w:color w:val="{color}"/>'
    out += f'<w:sz w:val="{sz}"/><w:szCs w:val="{sz}"/>'
    return out


def runs(text, **fmt):
    """Розбирає **жирний**, *курсив*, `код` на послідовність w:r."""
    out, pos = [], 0
    pat = re.compile(r'\*\*(.+?)\*\*|(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)|`(.+?)`')
    for m in pat.finditer(text):
        if m.start() > pos:
            out.append(_run(text[pos:m.start()], fmt))
        if m.group(1) is not None:
            out.append(_run(m.group(1), {**fmt, 'bold': True}))
        elif m.group(2) is not None:
            out.append(_run(m.group(2), {**fmt, 'italic': True}))
        else:
            out.append(_run(m.group(3), {**fmt, 'mono': True}))
        pos = m.end()
    if pos < len(text):
        out.append(_run(text[pos:], fmt))
    return ''.join(out) or _run('', fmt)


def _run(t, fmt):
    return (f'<w:r><w:rPr>{rpr(**fmt)}</w:rPr>'
            f'<w:t xml:space="preserve">{esc(t)}</w:t></w:r>')


def para(text, *, style=None, sz=SZ_BODY, bold=False, italic=False, color=None,
         align=None, num=None, ilvl=0, shade=None, rule=False, space_after=0,
         space_before=0, keep=False):
    """Порядок дочірніх елементів w:pPr фіксований схемою:
    pStyle, keepNext, numPr, pBdr, shd, spacing, ind, jc, rPr."""
    fmt = dict(bold=bold, italic=italic, color=color, sz=sz)
    ppr = '<w:pPr>'
    if style: ppr += f'<w:pStyle w:val="{style}"/>'
    if keep:  ppr += '<w:keepNext/>'
    if num:   ppr += f'<w:numPr><w:ilvl w:val="{ilvl}"/><w:numId w:val="{num}"/></w:numPr>'
    if rule:
        ppr += ('<w:pBdr><w:bottom w:val="single" w:sz="6" w:space="1" '
                f'w:color="{ORANGE}"/></w:pBdr>')
    elif shade == CALLOUT:
        ppr += ('<w:pBdr><w:left w:val="single" w:sz="18" w:space="6" '
                f'w:color="{ORANGE}"/></w:pBdr>')
    if shade: ppr += f'<w:shd w:val="clear" w:color="auto" w:fill="{shade}"/>'
    ppr += (f'<w:spacing w:before="{space_before}" w:after="{space_after}" '
            'w:line="276" w:lineRule="auto"/>')
    if shade == CALLOUT: ppr += '<w:ind w:left="170"/>'
    if align: ppr += f'<w:jc w:val="{align}"/>'
    ppr += f'<w:rPr>{rpr(**fmt)}</w:rPr></w:pPr>'
    body = '' if not text else runs(text, **fmt)
    return f'<w:p>{ppr}{body}</w:p>'


def table(rows):
    head, body = rows[0], rows[1:]
    cols = len(head)
    weights = [max(len(r[i]) for r in rows) or 1 for i in range(cols)]
    total = sum(weights)
    widths = [max(900, int(TBL_W * w / total)) for w in weights]
    widths[-1] += TBL_W - sum(widths)
    bord = ''.join(f'<w:{s} w:val="single" w:sz="4" w:space="0" w:color="auto"/>'
                   for s in ('top', 'left', 'bottom', 'right', 'insideH', 'insideV'))
    out = [f'<w:tbl><w:tblPr><w:tblW w:w="{TBL_W}" w:type="dxa"/><w:jc w:val="center"/>'
           f'<w:tblBorders>{bord}</w:tblBorders><w:tblLayout w:type="fixed"/>'
           '<w:tblLook w:val="04A0" w:firstRow="1" w:lastRow="0" w:firstColumn="1" '
           'w:lastColumn="0" w:noHBand="0" w:noVBand="1"/></w:tblPr><w:tblGrid>'
           + ''.join(f'<w:gridCol w:w="{w}"/>' for w in widths) + '</w:tblGrid>']
    for ri, row in enumerate(rows):
        head_row = (ri == 0)
        trpr = '<w:trPr><w:tblHeader/></w:trPr>' if head_row else ''
        out.append(f'<w:tr>{trpr}')
        for ci in range(cols):
            cell = row[ci] if ci < len(row) else ''
            shd = (f'<w:shd w:val="clear" w:color="auto" w:fill="{TBLHEAD}"/>'
                   if head_row else '')
            out.append(f'<w:tc><w:tcPr><w:tcW w:w="{widths[ci]}" w:type="dxa"/>{shd}'
                       '<w:vAlign w:val="center"/></w:tcPr>')
            out.append(para(cell, bold=head_row, color='FFFFFF' if head_row else None))
            out.append('</w:tc>')
        out.append('</w:tr>')
    out.append('</w:tbl>')
    out.append(para('', sz=12))          # відбивка після таблиці
    return ''.join(out)


def png_size(path):
    with open(path, 'rb') as fh:
        head = fh.read(24)
    if head[:8] != b'\x89PNG\r\n\x1a\n':
        raise SystemExit(f'{path}: не PNG')
    w, h = struct.unpack('>II', head[16:24])
    return w, h


def logo(tpl):
    w, h = png_size(os.path.join(tpl, 'word', 'media', 'image1.png'))
    cx = 1800000                          # ~4.7 см
    cy = int(cx * h / w)
    return (f'<w:p><w:pPr><w:spacing w:before="0" w:after="120"/>'
            f'<w:jc w:val="center"/></w:pPr><w:r><w:rPr>{ARIAL}</w:rPr><w:drawing>'
            f'<wp:inline distT="0" distB="0" distL="0" distR="0">'
            f'<wp:extent cx="{cx}" cy="{cy}"/><wp:docPr id="1" name="logo"/>'
            '<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/'
            'drawingml/2006/picture"><pic:pic><pic:nvPicPr>'
            '<pic:cNvPr id="1" name="logo"/><pic:cNvPicPr/></pic:nvPicPr>'
            '<pic:blipFill><a:blip r:embed="rId8"/><a:stretch><a:fillRect/>'
            '</a:stretch></pic:blipFill><pic:spPr>'
            f'<a:xfrm><a:off x="0" y="0"/><a:ext cx="{cx}" cy="{cy}"/></a:xfrm>'
            '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>'
            '</pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>')


BLOCK_START = re.compile(r'^\s*(#{1,6}\s|[-*]\s|\d+[.)]\s|\||>\s|---\s*$|\[\[)')


def is_block_start(ln):
    """Рядок починає новий блок, а не продовжує абзац."""
    return bool(ln.strip()) and bool(BLOCK_START.match(ln))


def strip_comments(md):
    """HTML-комментарі з boilerplate-файлів у документ не потрапляють."""
    return re.sub(r'<!--.*?-->', '', md, flags=re.S)


def expand_includes(md, base, depth=0):
    """[[INCLUDE:шлях]] — вставка стабільного блоку дослівно, без переказу.

    Шлях відносний до кореня репозиторію. Вкладеність до трьох рівнів: глибше —
    ознака циклу, і краще впасти, ніж зациклитись."""
    if depth > 3:
        raise SystemExit('[[INCLUDE]]: вкладеність понад три рівні — схоже на цикл')
    out = []
    for n, ln in enumerate(md.split('\n'), 1):
        m = re.match(r'^\s*\[\[INCLUDE:([^\]]+)\]\]\s*$', ln)
        if not m:
            out.append(ln); continue
        rel = m.group(1).strip()
        if rel.startswith('/') or '..' in rel:
            raise SystemExit(f'рядок {n}: [[INCLUDE]] бере лише шляхи в репозиторії')
        path = os.path.join(base, rel)
        if not os.path.isfile(path):
            raise SystemExit(f'рядок {n}: [[INCLUDE]] не знайшов {rel}')
        inc = strip_comments(open(path, encoding='utf-8').read())
        out.append(expand_includes(inc, base, depth + 1))
    return '\n'.join(out)


def _item(first, lines, i):
    """Пункт списку може продовжуватись наступним рядком — склеюємо."""
    chunk, j = [first], i + 1
    while j < len(lines) and lines[j].strip() and not is_block_start(lines[j]):
        chunk.append(lines[j].strip())
        j += 1
    return ' '.join(chunk), j


def convert(md, tpl):
    body, i, lines = [], 0, md.split('\n')
    while i < len(lines):
        ln = lines[i]
        s = ln.strip()
        if not s:
            i += 1; continue

        if s == '[[PAGEBREAK]]':
            body.append('<w:p><w:r><w:br w:type="page"/></w:r></w:p>'); i += 1; continue
        if s == '[[LOGO]]':
            body.append(logo(tpl)); i += 1; continue
        if s == '---':
            body.append(para('', rule=True, sz=2)); i += 1; continue

        if re.match(r'^#{6,}', s):
            raise SystemExit(f'рядок {i+1}: заголовків глибше пʼятого рівня немає — '
                             'перебудуй структуру, а не додавай рівень')
        if re.search(r'!\[', s):
            raise SystemExit(f'рядок {i+1}: зображень у клієнтських документах немає, '
                             'окрім логотипа через [[LOGO]]')
        if re.search(r'(?<!!)\[[^\]]+\]\([^)]+\)', s):
            raise SystemExit(f'рядок {i+1}: markdown-посилань немає — пиши адресу текстом, '
                             'клієнт читає документ у Word, а не в браузері')
        if re.match(r'^\[\[(?!LOGO\]\]|PAGEBREAK\]\]|INCLUDE:)', s):
            raise SystemExit(f'рядок {i+1}: невідома директива {s[:40]} — '
                             'є тільки [[LOGO]], [[PAGEBREAK]], [[INCLUDE:шлях]]')

        m = re.match(r'(#{1,5})\s+(.*)$', s)
        if m:
            lvl, txt = len(m.group(1)), m.group(2)
            if lvl == 1:
                body.append(para(txt, style='a3', sz=SZ_TITLE, bold=True, align='center',
                                 space_after=120))
            elif lvl == 2:
                body.append(para(txt, style='1', sz=SZ_H1, bold=True, color=ORANGE,
                                 align='center', space_before=240, space_after=120, keep=True))
            elif lvl == 3:
                body.append(para(txt, style='2', sz=SZ_H2, bold=True, color=ORANGE,
                                 space_before=200, space_after=80, keep=True))
            elif lvl == 4:
                body.append(para(txt, style='3', sz=SZ_H3, bold=True,
                                 space_before=160, space_after=60, keep=True))
            else:
                body.append(para(txt, style='4', sz=SZ_BODY, italic=True,
                                 space_before=120, space_after=40, keep=True))
            i += 1; continue

        if s.startswith('> '):
            body.append(para(s[2:], shade=CALLOUT, space_before=80, space_after=80))
            i += 1; continue

        m = re.match(r'^(\s*)([-*])\s+(.*)$', ln)
        if m:
            ilvl = min(len(m.group(1)) // 2, 8)
            txt, i = _item(m.group(3), lines, i)
            body.append(para(txt, num=NUM_BUL, ilvl=ilvl))
            continue

        m = re.match(r'^(\s*)(\d+)[.)]\s+(.*)$', ln)
        if m:
            ilvl = min(len(m.group(1)) // 2, 8)
            txt, i = _item(m.group(3), lines, i)
            body.append(para(txt, num=NUM_DEC, ilvl=ilvl))
            continue

        if s.startswith('|'):
            rows, j, sep = [], i, False
            while j < len(lines) and lines[j].strip().startswith('|'):
                cells = [c.strip() for c in lines[j].strip().strip('|').split('|')]
                # порожній рядок-форма (| | | |) — це РЯДОК ДАНИХ, а не роздільник:
                # all() на порожній послідовності дає True, і без перевірки
                # на непорожність анкета з полями під заповнення зникала
                if any(cells) and all(re.fullmatch(r':?-{2,}:?', c) for c in cells if c):
                    sep = True
                else:
                    rows.append(cells)
                j += 1
            if not sep:
                raise SystemExit(f'рядок {i+1}: таблиця без рядка-роздільника `|---|`. '
                                 'Без нього не видно, який рядок є шапкою')
            if len(rows) < 2:
                raise SystemExit(f'рядок {i+1}: у таблиці немає жодного рядка даних')
            body.append(table(rows)); i = j; continue

        # абзац: послідовні прості рядки — один абзац, як у markdown.
        # Без склеювання «жирний **розрив між рядками**» протікає розміткою,
        # а суцільний текст розсипається на окремі абзаци.
        chunk = [s]
        j = i + 1
        while j < len(lines) and lines[j].strip() and not is_block_start(lines[j]):
            chunk.append(lines[j].strip())
            j += 1
        body.append(para(' '.join(chunk), space_after=60))
        i = j
    return ''.join(body)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('src'); ap.add_argument('dst')
    ap.add_argument('--title', default='')
    ap.add_argument('--template', default=TPL)
    a = ap.parse_args()

    tpl = os.path.abspath(a.template)
    if not os.path.isdir(tpl):
        raise SystemExit(f'немає шаблона: {tpl}')
    repo = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
    md = strip_comments(open(a.src, encoding='utf-8').read())
    md = expand_includes(md, repo)

    doc = (f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
           f'<w:document {NS}><w:body>{convert(md, tpl)}{SECT}</w:body></w:document>')

    title = a.title or next((l[2:].strip() for l in md.split('\n')
                             if l.startswith('# ')), 'Документ')
    now = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')

    tmp = tempfile.mkdtemp()
    try:
        pkg = os.path.join(tmp, 'pkg')
        shutil.copytree(tpl, pkg)
        open(os.path.join(pkg, 'word', 'document.xml'), 'w', encoding='utf-8').write(doc)
        core = os.path.join(pkg, 'docProps', 'core.xml')
        c = open(core, encoding='utf-8').read()
        open(core, 'w', encoding='utf-8').write(
            c.replace('__TITLE__', esc(title)).replace('__DATE__', now))
        dst = os.path.abspath(a.dst)
        if os.path.exists(dst): os.remove(dst)
        with zipfile.ZipFile(dst, 'w', zipfile.ZIP_DEFLATED) as z:
            first = os.path.join(pkg, '[Content_Types].xml')
            z.write(first, '[Content_Types].xml')
            for root, _, files in os.walk(pkg):
                for f in sorted(files):
                    p = os.path.join(root, f)
                    rel = os.path.relpath(p, pkg).replace(os.sep, '/')
                    if rel == '[Content_Types].xml': continue
                    z.write(p, rel)
        print(f'{dst}  ({os.path.getsize(dst) // 1024} КБ)')
    finally:
        shutil.rmtree(tmp)


if __name__ == '__main__':
    main()
