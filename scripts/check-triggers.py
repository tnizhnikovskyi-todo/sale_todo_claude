#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Тригерні фрази в тексті скіла мусять існувати дослівно в description того скіла,
який ними запускається.

Розходження тут не ловить жодна інша перевірка і не видно оком: ланцюг виглядає
цілим, а фраза, якою один скіл радить викликати наступний, не збігається з фразою,
на яку той насправді тригериться. Виявиться це на сейлі, який продиктує фразу
й нічого не отримає.

Що вважається тригерною фразою: **усі** цитати в розділі «Наступний крок» і **жирні**
цитати будь-де в тексті (`**"фраза"**` — домашня конвенція). Друге важливо, бо
передача в інший скіл живе не тільки в кінці файлу: у Кроці 0 скіл часто відмовляється
й називає того, кому запит належить.

Пари шукаються **в межах блоку** — пункту списку, абзацу, рядка таблиці. Перша версія
брала «найближчий скіл після фрази» по всьому тексту і давала хибні спрацювання,
перетинаючи межу пункту. Блок без імені скіла — фраза мусить знайтись у description
хоч якогось скіла. Ціль з іншого треку (скіла немає в цьому репозиторії) пропускається.
"""
import re, sys, glob, os

norm = lambda t: re.sub(r'\s+', ' ', t).strip().lower()
# «по [компанія]», «для [компанія]», «[галузь]» — плейсхолдери, не частина фрази
strip_ph = lambda t: norm(re.sub(r'\s*(по|для|з|із)?\s*\[[^\]]+\]\s*', ' ', t))
BLOCK = re.compile(r'\n\s*>?\s*(?:[•\-*]|\d+\.)\s*|\n\n|\n\|')


def main():
    skills = {os.path.basename(os.path.dirname(f)): f
              for f in glob.glob('plugins/*/skills/*/SKILL.md')}
    if not skills:
        print('  ✗ жодного SKILL.md не знайдено — перевірка безпредметна')
        return 1
    descs = {}
    for name, f in skills.items():
        s = open(f, encoding='utf-8').read()
        m = re.search(r'^---\n(.*?)\n---\n', s, re.S)
        descs[name] = norm(m.group(1)) if m else ''

    fail = total = 0
    for name, f in sorted(skills.items()):
        s = open(f, encoding='utf-8').read()
        i = s.find('## Наступний крок')
        if i < 0:
            print(f'  ✗ {name}: немає розділу «Наступний крок»'); fail = 1
        body = s[s.index('\n---\n', 5):]        # без frontmatter: там фрази оголошуються
        nxt = s[i:] if i >= 0 else ''
        j = nxt.find('\n## ')
        nxt = norm(nxt[:j] if j > 0 else nxt)

        for blk in BLOCK.split(body):
            b = norm(blk)
            in_next = bool(b) and b in nxt
            names = [(m.start(), m.group(1)) for m in re.finditer(r'`([a-z][a-z0-9-]+)`', b)]
            # у «Наступному кроці» — усі цитати; будь-де ще — тільки жирні
            found = re.finditer(r'"([^"]{6,70})"', b) if in_next else re.finditer(r'\*\*"([^"]{6,70})"\*\*', b)
            for q in found:
                core = strip_ph(q.group(1))
                if not core:
                    continue
                after = [n for pos, n in names if pos > q.end()]
                before = [n for pos, n in names if pos < q.start()]
                named = (after[:1] or before[-1:])
                if named and named[0] not in skills:
                    continue          # ціль іншого треку
                total += 1
                where = named if named else list(descs)
                if not any(core in descs[t] for t in where):
                    tail = f' → {named[0]}' if named else ''
                    scope = 'description цілі' if named else 'description жодного скіла'
                    print(f'  ✗ {name}{tail}: фрази «{core}» немає в {scope}')
                    fail = 1

    print(f'  тригерних фраз звірено: {total}')
    return fail


if __name__ == '__main__':
    sys.exit(main())
