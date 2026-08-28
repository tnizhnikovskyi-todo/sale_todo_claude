#!/usr/bin/env python3
# ЗГЕНЕРОВАНО з scripts/check-humizer.py скриптом scripts/sync-shared.sh.
# Не правити тут — правки затираються. Канонічне джерело: scripts/check-humizer.py
# -*- coding: utf-8 -*-
"""Машинна перевірка Humizer для клієнтських документів (регістр 3).

    python3 scripts/check-humizer.py файл.md|файл.docx [...]

Humizer оголошений блокуючим у кожному клієнтському скілі, але доводився лише
вичиткою. Тут — та частина, яку можна перевірити механічно: усе з розділу
«Прибрати повністю» (`registers.md` §3) і числові параметри з §4 «Фільтр чутливого».

Що НЕ перевіряється і лишається за людиною: тон, метафори, розмовні довіски,
чи зрозуміє це людина без IT-бекграунду. Перевірка не заміняє Humizer —
вона ловить те, що прослизає при вичитці на п'ятому документі підряд.

Працює і по чернетці `.md`, і по зібраному `.docx`: Humizer іде по чернетці,
а `.docx` — остання лінія оборони перед клієнтом.
"""
import re, sys, zipfile

# ── ID реєстрів журналу: «G-12», «Q-7», «ST-3» — головне, що не має дійти до клієнта
IDS = re.compile(r'(?<![A-Za-zА-Яа-я0-9])(?:ST|D|X|G|Q|C|P|R|A)-\d{1,3}(?![0-9])')
TAGS = re.compile(r'\[(?:КО|ВО|ПП)\]')
# §13: блок питань до сейла живе у внутрішньому виході, у клієнтський не потрапляє
ASKS = re.compile(r'Питання до сейла|Без відповіді:', re.I)
LEVELS = re.compile(r'[🔴🟡🟢🟠]')
# Fathom — інструмент запису дому; посилання виглядає як fathom.video/share/<токен>.
# tldv лишається в переліку: старі транскрипти нікуди не зникли.
TRANSCRIPT = re.compile(r'Speaker\s*\d|fathom\.video|fathom|tldv|tl;dv|\b\d{1,2}:\d{2}:\d{2}\b', re.I)
# ── §4 фільтр чутливого: механіка розрахунку
MECHANICS = [
    (re.compile(r'коефіцієнт', re.I), 'коефіцієнт вилки — механіка розрахунку (§4)'),
    (re.compile(r'ставк\w*\s+(?:за\s+годину|впровадження|дискавері)', re.I),
     'ставка за годину — комерційний параметр (§4)'),
    (re.compile(r'€\s*/\s*год|EUR\s*/\s*год|євро\s+за\s+годину', re.I),
     'ставка за годину цифрою (§4)'),
    (re.compile(r'[×x]\s*[123](?:[,.]5)?\b'), 'множник вилки (§4)'),
    (re.compile(r'стоп-сигнал', re.I), 'стоп-сигнал — внутрішній інструмент (§4)'),
    (re.compile(r'біл\w+ плям', re.I), 'білі плями як перелік прогалин (§4)'),
]
# ── §3 жаргон: таблиця «Було → Стало», дослівно
JARGON = [
    (re.compile(r'(?<![а-яА-Я])scope(?![а-яА-Я])', re.I), 'scope → обсяг / межі робіт'),
    (re.compile(r'стейкхолдер', re.I), 'стейкхолдер → учасник / відповідальний'),
    (re.compile(r'deliverable', re.I), 'deliverable → результат'),
    (re.compile(r'as-is|to-be', re.I), 'As-Is / To-Be → поточний / цільовий стан'),
    (re.compile(r'pain\s*points?|bottleneck', re.I), 'pain points → вузькі місця'),
    (re.compile(r'master\s*data', re.I), 'master data → основний довідник'),
    (re.compile(r'(?<![а-яА-Я])(?:BoM|MO)(?![а-яА-Я\w])'), 'BoM / MO → специфікація / замовлення на виробництво'),
    (re.compile(r'(?<![A-Za-z])(?:FIFO|FEFO|AVCO)(?![A-Za-z])'), 'FIFO / FEFO / AVCO → пояснити принцип у дужках'),
    (re.compile(r'здійснюється|в розрізі|в частині(?!\s+[а-я]*\s*робіт)', re.I), 'канцелярит (§3)'),
]


def text_of(path):
    if path.endswith('.docx'):
        d = zipfile.ZipFile(path).read('word/document.xml').decode('utf-8')
        import html
        return ' '.join(html.unescape(m) for m in
                        re.findall(r'<w:t(?:\s[^>]*)?>(.*?)</w:t>', d, re.S))
    return open(path, encoding='utf-8').read()


def check(path):
    bad = []
    try:
        txt = text_of(path)
    except Exception as e:
        return [f'не читається: {e}']

    # директиви розмітки чернетки — не текст документа
    if path.endswith('.md'):
        txt = re.sub(r'\[\[[A-Z]+(?::[^\]]+)?\]\]', ' ', txt)

    for m in dict.fromkeys(IDS.findall(txt)):
        bad.append(f'ID реєстру в клієнтському тексті: {m} (§3 «прибрати повністю»)')
    for m in dict.fromkeys(TAGS.findall(txt)):
        bad.append(f'тег пріоритету: {m} (§3)')
    if LEVELS.search(txt):
        bad.append('маркер рівня 🔴/🟡 — внутрішній (§3)')
    for m in dict.fromkeys(TRANSCRIPT.findall(txt)):
        bad.append(f'слід транскрипту: {m!r} (§3)')
    m = ASKS.search(txt)
    if m:
        bad.append(f'питання до сейла в клієнтському документі: «{m.group(0)}» (§13 конвенцій)')
    for rx, why in MECHANICS + JARGON:
        m = rx.search(txt)
        if m:
            bad.append(f'{why} — знайдено «{m.group(0)}»')
    return bad


def main():
    if len(sys.argv) < 2:
        raise SystemExit('вжиток: check-humizer.py файл.md|файл.docx [...]')
    fail = 0
    for p in sys.argv[1:]:
        bad = check(p)
        print(f'▸ {p}')
        for b in bad:
            print(f'  ✗ {b}')
        if bad:
            fail = 1
        else:
            print('  ок — внутрішніх слідів немає')
    sys.exit(fail)


if __name__ == '__main__':
    main()
