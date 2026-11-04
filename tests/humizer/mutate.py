#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Мутаційна перевірка самого тесту мовних правил: ламаємо чекер по одному місцю
і переконуємось, що scripts/test-humizer.py червоніє. Пастка «зеленої перевірки»
з CLAUDE.md — тест, який не падає на зламаному правилі, нічого не доводить.

    python3 tests/humizer/mutate.py      # з кореня репозиторію; ~1 хв, у CI не входить

Мутація прописана заміною рядка: якщо рядок у чекері змінили, assert скаже,
яку мутацію оновити.
"""
import sys, subprocess, os, tempfile
S = tempfile.mkdtemp()
src=open('scripts/check-humizer.py',encoding='utf-8').read()
muts={
 'межа слова без апострофа': ("WL = rf'(?<![\\w{APOS}-])'", "WL = rf'(?<![\\w-])'"),
 'одне закінчення прикметника випало': ("ADJ = '(?:ий|а|е|і|ого|ому|ої|ій|у|ою|их|им|ими|ім)'","ADJ = '(?:ий|а|е|і|ого|ому|ої|ій|у|ою|их|им|ими)'"),
 'права межа слова зникла (стемінг)': ("    rx = re.compile(f'{WL}(?:{alts}){WR}', re.I)","    rx = re.compile(f'{WL}(?:{alts})', re.I)"),
 'апостроф не перевіряється': ("    if ap:\n        e('апостроф'","    if False:\n        e('апостроф'"),
 'кальки стали помилкою': ("            w('калька'","            e('калька'"),
 'перенос рядка у фразі не ловиться': ("alts = '|'.join(f.replace(' ', r'\\s+') for f in forms)","alts = '|'.join(f.replace(' ', r' +') for f in forms)"),
 'діапазон «від…до» ловиться': ("    (W('з метою'), 'щоб, для'),","    (W('з метою'), 'щоб, для'),\n    (re.compile(r'від\\s+\\d+\\s+до'), 'x'),"),
 'латиниця в слові не ловиться': ("    if mixed:\n","    if False:\n"),
 'російські букви не ловляться': ("    if ru:\n","    if False:\n"),
 'невидимі не ловляться': ("    if inv:\n","    if False:\n"),
 'бот-хвости стали попередженням': ("            e('бот-хвіст'","            w('бот-хвіст'"),
 '«–» з пробілами в членах діапазону ловиться': ("EN_NUMS = re.compile(r'(?:(?<=[^\\d\\s])|(?<=[^\\d][^\\S\\n])|^)","EN_NUMS = re.compile(r'(?:"),
 'текст .docx склеюється пробілом': ("            paras.append(''.join(","            paras.append(' '.join("),
 'лапки не ловляться': ("    hits = STRAIGHT_QUOTES.findall(p)","    hits = []"),
 'діапазон через дефіс не ловиться': ("    hits = RANGE_HYPHEN.findall(txt)","    hits = []"),
 'тире-зʼєднувач не ловиться': ("        hits = BOLD_DASH.findall(p)","        hits = []"),
 'зʼєднувач посеред речення ловиться': ("BOLD_DASH = re.compile(r'^[^\\S\\n]*(?:[-*·•][^\\S\\n]+|\\d+[.)][^\\S\\n]+)?", "BOLD_DASH = re.compile(r'(?:"),
 'внутрішні „…“ ловляться': ("|“[^”“\\n]{1,200}”')", "|[“„][^”“\\n]{1,200}[”“]')"),
 # ── мʼякий старт (рішення власника 2026-11-04)
 'мʼякий старт не діє': ("    if not strict(today):\n        note", "    if False:\n        note"),
 'дата строгості зсунута на день': ("STRICT_FROM = datetime.date(2026, 11, 19)", "STRICT_FROM = datetime.date(2026, 11, 20)"),
 'останній день мʼякого старту вже строгий': (") >= STRICT_FROM", ") >= STRICT_FROM - datetime.timedelta(days=1)"),
 'межа включно зʼїхала (> замість >=)': (") >= STRICT_FROM", ") > STRICT_FROM"),
 'старі правила теж мʼякі': ("PHASED = ('букви',", "PHASED = ('ID', 'механіка', 'букви',"),
 'русизм випав з мʼякого старту': ("'апостроф', 'русизм', 'дієприкметник'", "'апостроф', 'дієприкметник'"),
 'попередження без дати': ("note = f' [мʼякий старт: з {STRICT_FROM.isoformat()} це помилка]'", "note = ' [мʼякий старт]'"),
 '--today ігнорується': ("        fs = findings(p, args.today)", "        fs = findings(p)"),
}
bad=0
for name,(a,b) in muts.items():
    assert src.count(a)==1,(name,src.count(a))
    p=os.path.join(S,'m.py'); open(p,'w',encoding='utf-8').write(src.replace(a,b))
    r=subprocess.run([sys.executable,'-B','scripts/test-humizer.py'],env={**os.environ,'HUMIZER_CHECKER':p},capture_output=True,text=True)
    n=r.stdout.count('  ✗'); bad+= r.returncode==0
    print(('✓ ловить' if r.returncode else '✗ НЕ ЛОВИТЬ'), name, f'({n} порушень)')
print('мутацій', len(muts), 'пропущено', bad)
sys.exit(1 if bad else 0)
