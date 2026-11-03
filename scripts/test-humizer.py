#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Тести мовних правил check-humizer.py — у обидва боки.

    python3 scripts/test-humizer.py [-v]

Правило дому (CLAUDE.md, «пастка зеленої перевірки»): кожну перевірку прогнати
негативним тестом на КОЖНОМУ варіанті формулювання, яке вона допускає. Тому:

1. Автокейси: на кожну словоформу з реєстру FORMS (усі форми W(), усі закінчення A())
   будується речення — і перевірка мусить спрацювати саме своїм класом. Окремо — та
   сама форма з великої букви і з переносом рядка всередині фрази.
2. Ручні кейси `tests/humizer/cases.txt`: регекспи, яких не перелічиш формами
   («згідно графіку»), і позитивні — те, що ловитись НЕ мусить: стоп-лист норм,
   «від 320 до 480 годин», «в годинах», безособові форми, «варто перевірити».
3. Фікстури: `tests/humizer/dirty/*.md` — кожен файл мусить дати свій клас
   (першим рядком `<!-- очікується: E клас, W клас -->`) і код виходу за рівнем;
   `tests/humizer/clean/*.md` — нуль помилок і нуль попереджень.

Падає з кодом 1 і переліком того, що не спрацювало або спрацювало хибно.
"""
import importlib.util
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# HUMIZER_CHECKER — підмінити чекер зламаною копією: мутаційна перевірка самого тесту
CHECKER = os.environ.get('HUMIZER_CHECKER') or os.path.join(ROOT, 'scripts', 'check-humizer.py')
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location('check_humizer', CHECKER)
hz = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hz)

VERBOSE = '-v' in sys.argv
tmp = tempfile.mkdtemp()
fails = []
counts = {'auto': 0, 'neg': 0, 'pos': 0, 'dirty': 0, 'clean': 0}


def run(text, name='case.md'):
    p = os.path.join(tmp, name)
    with open(p, 'w', encoding='utf-8') as f:
        f.write('# Т\n\n' + text + '\n')
    return hz.findings(p)


def has(fs, lvl, cls):
    return any(l == lvl and c == cls for l, c, _ in fs)


def show(fs):
    return '; '.join(f'{l}/{c}' for l, c, _ in fs) or 'нічого'


# ── 1. автокейси з реєстру форм
CLASS_OF = {}
for rx, _ in hz.RUSSISMS:
    CLASS_OF[rx] = (hz.ERR, 'русизм')
for rx, _ in hz.PARTICIPLES:
    CLASS_OF[rx] = (hz.ERR, 'дієприкметник')
for rx in hz.BOT_TAILS:
    CLASS_OF[rx] = (hz.ERR, 'бот-хвіст')
for rx, _ in hz.CALQUES:
    CLASS_OF[rx] = (hz.WARN, 'калька')
for rx, _ in hz.CANCELLARY:
    CLASS_OF[rx] = (hz.WARN, 'канцелярит')
for rx in hz.AI_STAMPS:
    CLASS_OF[rx] = (hz.WARN, 'штамп')

orphan = [rx.pattern[:60] for rx in hz.FORMS if rx not in CLASS_OF]
if orphan:
    fails.append(f'форми зареєстровані, але правило не в жодному класі: {orphan}')

# закінчення прикметника — незалежний еталон, не hz.ENDINGS: інакше випале з ADJ
# закінчення тихо випадає і з тесту (мутаційна перевірка це показала)
ENDINGS = ['ий', 'а', 'е', 'і', 'ого', 'ому', 'ої', 'ій', 'у', 'ою', 'их', 'им', 'ими', 'ім']
if hz.ENDINGS != ENDINGS:
    fails.append(f'закінчення прикметника в чекері {hz.ENDINGS} ≠ еталон {ENDINGS}')

for rx, forms in hz.FORMS.items():
    if rx not in CLASS_OF:
        continue
    lvl, cls = CLASS_OF[rx]
    if rx in hz.STEMS:   # прикметник: форми з еталонних закінчень, не з чекера
        forms = [st + en for st in hz.STEMS[rx] for en in ENDINGS]
    for form in forms:
        variants = [f'Далі {form} у документі.', f'{form[0].upper() + form[1:]} у документі.']
        if ' ' in form:
            variants.append('Далі ' + form.replace(' ', '\n', 1) + ' у документі.')
        for v in variants:
            counts['auto'] += 1
            fs = run(v)
            if not has(fs, lvl, cls):
                fails.append(f'НЕ ЛОВИТЬ форму [{lvl} {cls}] «{form}» у «{v!r}» → {show(fs)}')
            # форма з чужим апострофом («невід'ємний») законно дає ще й помилку апострофа
            elif lvl == hz.WARN and any(l == hz.ERR and not (c == 'апостроф' and re.search("['’‘`′]", form))
                                        for l, c, _ in fs):
                fails.append(f'попередження блокує: «{v}» → {show(fs)}')

# ── 2. ручні кейси
case_file = os.path.join(ROOT, 'tests', 'humizer', 'cases.txt')
for n, line in enumerate(open(case_file, encoding='utf-8'), 1):
    line = line.rstrip('\n')
    if not line.strip() or line.lstrip().startswith('#'):
        continue
    head, _, text = line.partition('|')
    text = text.strip().replace('\\n', '\n')
    text = re.sub(r'\\u([0-9a-fA-F]{4})', lambda m: chr(int(m.group(1), 16)), text)
    head = head.split()
    kind = head[0]
    if kind == 'OK':
        counts['pos'] += 1
        fs = run(text)
        if fs:
            fails.append(f'cases.txt:{n} ХИБНЕ СПРАЦЮВАННЯ на «{text}» → {show(fs)}')
        elif VERBOSE:
            print(f'  ✓ не хибує: {text}')
    elif kind == 'NO':
        counts['pos'] += 1
        cls = head[1]
        fs = run(text)
        if any(c == cls for _, c, _ in fs):
            fails.append(f'cases.txt:{n} ХИБНЕ [{cls}] на «{text}» → {show(fs)}')
    elif kind in (hz.ERR, hz.WARN):
        counts['neg'] += 1
        cls = head[1]
        fs = run(text)
        if not has(fs, kind, cls):
            fails.append(f'cases.txt:{n} НЕ ЛОВИТЬ [{kind} {cls}] «{text}» → {show(fs)}')
        elif kind == hz.WARN and any(l == hz.ERR for l, _, _ in fs):
            fails.append(f'cases.txt:{n} попередження блокує: «{text}» → {show(fs)}')
        elif VERBOSE:
            print(f'  ✓ {kind} {cls}: {text}')
    else:
        fails.append(f'cases.txt:{n}: невідомий вид кейсу «{kind}»')


# ── 3. фікстури — через CLI, щоб перевірити і коди виходу
def cli(path):
    r = subprocess.run([sys.executable, '-B', CHECKER, path], capture_output=True, text=True)
    return r.returncode, r.stdout


fx = os.path.join(ROOT, 'tests', 'humizer')
for name in sorted(os.listdir(os.path.join(fx, 'dirty'))):
    path = os.path.join(fx, 'dirty', name)
    first = open(path, encoding='utf-8').readline()
    m = re.search(r'очікується:\s*(.+?)\s*-->', first)
    if not m:
        fails.append(f'dirty/{name}: немає першого рядка <!-- очікується: … -->'); continue
    want = [tuple(x.split()) for x in m.group(1).split(',')]
    fs = hz.findings(path)
    counts['dirty'] += 1
    for lvl, cls in want:
        if not has(fs, lvl, cls):
            fails.append(f'dirty/{name}: не спрацював [{lvl} {cls}] → {show(fs)}')
    rc, _ = cli(path)
    need_rc = 1 if any(l == hz.ERR for l, _ in want) else 0
    if rc != need_rc:
        fails.append(f'dirty/{name}: код виходу {rc}, очікувався {need_rc}')
for name in sorted(os.listdir(os.path.join(fx, 'clean'))):
    path = os.path.join(fx, 'clean', name)
    counts['clean'] += 1
    rc, out = cli(path)
    if rc != 0 or '⚠' in out:
        fails.append(f'clean/{name}: має бути чистим, а дає:\n' + out)
    # те саме після складання: .docx — остання лінія, і текст там добувається інакше
    docx = os.path.join(tmp, name[:-3] + '.docx')
    mk = subprocess.run([sys.executable, '-B', os.path.join(ROOT, 'scripts', 'make-docx.py'), path, docx,
                         '--title', name[:-3]], capture_output=True, text=True, cwd=ROOT)
    if mk.returncode != 0:
        fails.append(f'clean/{name}: не складається в .docx — {mk.stderr.strip()[-200:]}')
        continue
    rc, out = cli(docx)
    if rc != 0 or '⚠' in out:
        fails.append(f'clean/{name}.docx: має бути чистим, а дає:\n' + out)

# Word ріже слово на пробіжки посеред. Гомогліф у другій половині мусить ловитись і так:
# «Скл» + «a» (латинська) + «дський» — одне слово, а не три
import zipfile
src_md = os.path.join(tmp, 'split.md')
open(src_md, 'w', encoding='utf-8').write('# Т\n\nСкладський облік і закупівлі.\n')
d1, d2 = os.path.join(tmp, 'split.docx'), os.path.join(tmp, 'split2.docx')
subprocess.run([sys.executable, '-B', os.path.join(ROOT, 'scripts', 'make-docx.py'), src_md, d1],
               capture_output=True, cwd=ROOT)
zi = zipfile.ZipFile(d1)
with zipfile.ZipFile(d2, 'w', zipfile.ZIP_DEFLATED) as zo:
    for it in zi.infolist():
        b = zi.read(it.filename)
        if it.filename == 'word/document.xml':
            x = b.decode('utf-8')
            if 'Складський' not in x:
                fails.append('split.docx: у складеному тексті немає «Складський» — тест не діє')
            b = x.replace('Складський', ('Скл</w:t></w:r><w:r><w:t xml:space="preserve">a</w:t></w:r>'
                                             '<w:r><w:t xml:space="preserve">дський'), 1).encode('utf-8')
        zo.writestr(it, b)
counts['dirty'] += 1
if not has(hz.findings(d2), hz.ERR, 'букви'):
    fails.append('.docx: гомогліф у слові, розрізаному на пробіжки, не ловиться')

print(f"▸ Humizer: автокейсів по формах {counts['auto']} · ручних негативних {counts['neg']} · "
      f"позитивних {counts['pos']} · брудних фікстур {counts['dirty']} · чистих {counts['clean']}")
for f in fails:
    print('  ✗', f)
if fails:
    print(f'Є порушення: {len(fails)}', file=sys.stderr)
    sys.exit(1)
print('OK — мовні правила Humizer ловлять своє і не хибують')
