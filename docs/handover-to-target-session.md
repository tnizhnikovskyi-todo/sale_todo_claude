# Чекліст для сесії на `todoltd/claude-methodology-marketplace`

> ✅ **Виконано.** Перенос зроблений, PR
> [todoltd/claude-methodology-marketplace#3](https://github.com/todoltd/claude-methodology-marketplace/pull/3).
> Файл лишається як запис того, що саме робилось і за якими критеріями приймалось.
> Повторно не виконувати.

Виконувати згори вниз. Кожен крок має **критерій приймання** — не переходити далі,
поки він не виконаний. Повний контекст і обґрунтування — `docs/migration-plan.md`
у джерелі; тут тільки дії.

| | |
|---|---|
| Джерело | `tnizhnikovskyi-todo/sale_todo_claude`, тег **`v0.3.0`** |
| Що переносимо | 3 плагіни (18 скілів) + контракти, перевірки, ресурси, фікстури, звіти |
| Чого НЕ переносимо | `CLAUDE.md`, `.gitignore`, CI, `README.md`, `CHANGELOG.md` джерела |
| Готова автоматизація | `.github/workflows/sync-to-methodology.yml` у джерелі — увімкнути **після** цього переносу |

---

## 0. Що знати до першої команди

Три речі, які вже заміряні й через які не варто винаходити коротший шлях:

1. **Посиланням плагін підключити не можна.** `source` на плагін у підкаталозі чужого
   репозиторію ставиться і дає **нуль скілів**: CLI клонує репозиторій і вважає
   плагіном його корінь. Рядок `√ Successfully installed` при цьому є. Тому потрібні
   справжні файли в цілі.
2. **Сабмодуль теж не годиться.** Працює лише при клоні з `--recurse-submodules`,
   а CLI клонує без нього: установка падає з `Source path does not exist`.
3. **Манифест цілі генерується** (`gen-manifest.py`), тому записи фази руками
   не дописуються — вони затерлись би.

---

## 1. Гілка й джерело

```bash
git checkout -b feature/sales-phase
git clone --depth 1 --branch v0.3.0 \
  https://github.com/tnizhnikovskyi-todo/sale_todo_claude /tmp/sales-src
```

**Приймання:** `/tmp/sales-src/scripts/our-plugins.txt` містить три рядки.

## 2. Перенести дерево

`PLUGIN_ROOT` — каталог плагінів цього репозиторію (типово `plugins`).
`sales-phase/` — окремий каталог для спільних частин фази, щоб не збігтись
із вашими `shared/`, `scripts/`, `assets/`.

```bash
PLUGIN_ROOT=plugins
for p in $(sed 's/#.*//' /tmp/sales-src/scripts/our-plugins.txt | sed '/^[[:space:]]*$/d'); do
  rm -rf "$PLUGIN_ROOT/$p"
  cp -a "/tmp/sales-src/plugins/$p" "$PLUGIN_ROOT/$p"
done
mkdir -p sales-phase
for d in shared scripts assets tests docs; do
  rm -rf "sales-phase/$d"; cp -a "/tmp/sales-src/$d" "sales-phase/$d"
done
```

**Приймання:** `ls $PLUGIN_ROOT` показує три каталоги `odoo19-sales-*` поряд
із вашими фазами; `sales-phase/scripts/our-plugins.txt` на місці.

## 3. Манифест і перелік зовнішніх плагінів

```bash
# фазу — в перелік, інакше повний реліз методології знесе її каталоги
$EDITOR .claude-plugin/external-plugins.txt     # додати три плагіни фази + category
python3 gen-manifest.py .
claude plugin validate .
```

**Приймання:** `grep -c odoo19-sales .claude-plugin/external-plugins.txt` → 3;
у згенерованому `marketplace.json` є три записи фази; `validate` зелений.

## 4. Перевірки фази — у ВАШОМУ дереві

```bash
cd sales-phase
PLUGDIR=../$PLUGIN_ROOT ./scripts/check-shared.sh
PLUGDIR=../$PLUGIN_ROOT ./scripts/check-skills.sh
PLUGDIR=../$PLUGIN_ROOT python3 scripts/check-triggers.py
./scripts/test-docx.sh
cd ..
```

**Приймання:** усі чотири зелені. `check-skills.sh` мусить написати
`Перевірено скілів: 18` — якщо менше, `PLUGDIR` указує не туди; якщо більше,
перевірка зачепила ваші фази (не мусить: межа дії — `our-plugins.txt`).

> Ці перевірки **не торкаються ваших плагінів** за конструкцією: вони читають
> `our-plugins.txt`, а не глобують каталог. Перевірено на макеті з чужою фазою поруч.

## 5. Установка з чистого клону — головний крок

```bash
git add -A && git commit -m "Фаза продажів 0.3.0"
git clone . /tmp/target-check && cd /tmp/target-check
claude plugin marketplace add .
claude plugin install odoo19-sales-prep@<ім'я вашого маркетплейсу>
claude plugin details odoo19-sales-prep@<ім'я> | head -20
```

**Приймання — і це найважливіше в усьому переносі:**

- `Skills (7)` для `prep`, `(6)` для `demo`, `(5)` для `offer`. **`Skills (0)` означає
  провал**, навіть якщо установка написала «успішно»;
- конвейєр `.docx` збирається з каталогу встановленого скіла:

```bash
d=~/.claude/plugins/cache/*/odoo19-sales-demo/*/plugins/odoo19-sales-demo/skills/presale-pack-builder
python3 $d/scripts/make-docx.py $d/assets/questionnaire/анкета.md /tmp/t.docx --title Тест
python3 $d/scripts/check-docx.py /tmp/t.docx
python3 $d/scripts/check-humizer.py /tmp/t.docx
```

Прибрати за собою: `claude plugin uninstall`, `marketplace remove`, `rm -rf /tmp/target-check`.

## 6. PR

PR у дефолтну гілку. У тілі — що перенесено, що не торкалось, і рядок про пройдений
крок 5 із фактичними числами скілів.

---

## Чого не робити

- **Не правити** `plugins/*/skills/*/references/*` і копії інструментарію `.docx`
  усередині скілів — вони генеровані з `sales-phase/shared/` і `sales-phase/scripts/`.
  `check-shared.sh` упаде і відкатить правку.
- **Не приводити ваші скіли** до конвенцій фази продажів. Межа дії існує саме для цього.
- **Не зливати CHANGELOG** фази у ваш потік версій — нумерація `0.1.0 → 0.3.0` описує
  тільки цю фазу.
- **Не переносити робочі артефакти** прогонів (журнали, КП, анкети конкретних угод):
  у них назви компаній і суми. У git джерела їх немає, у `/tmp` — є.
- **Не класти `category` у `plugin.json`** — це поле запису маркетплейсу.

---

## Що переказати назад у першу сесію

Щоб вона довела джерело до узгодженого стану, потрібні чотири факти:

1. фактичний `PLUGIN_ROOT` цілі;
2. чи лишилась назва `sales-phase/` для спільних частин;
3. **ім'я вашого маркетплейсу** — під нього переписується `README.md` джерела
   і команди установки;
4. чи версія плагінів фази лишається окремою (`0.3.0`), чи приймає вашу схему —
   від цього залежить правило парності в `check-manifests.sh` і крок звірки версій
   у sync-workflow.

Після цього в джерелі: `README.md` → «переїхало туди», секрет
`METHODOLOGY_SYNC_TOKEN`, і автотригер у `sync-to-methodology.yml` розкомментувати.
