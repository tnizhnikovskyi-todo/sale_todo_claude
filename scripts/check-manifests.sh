#!/usr/bin/env bash
# Манифести маркетплейсу і плагінів: узгодженість між собою і з деревом каталогів.
# Якщо в середовищі є Claude Code CLI — додатково прогоняє його власний валідатор.
set -uo pipefail
export LC_ALL=C.utf8
cd "$(dirname "$0")/.."
. ./scripts/lib-scope.sh

fail=0

echo "▸ узгодженість манифестів"
python3 - <<'PY' || fail=1
import json, glob, os, sys
bad = 0
m = json.load(open('.claude-plugin/marketplace.json'))
declared = {p['name']: p for p in m['plugins']}

ours = [l.split('#')[0].strip() for l in open('scripts/our-plugins.txt', encoding='utf-8')]
ours = [o for o in ours if o]
root = os.environ.get('PLUGDIR', 'plugins')
for f in [f'{root}/{o}/.claude-plugin/plugin.json' for o in ours if os.path.isfile(f'{root}/{o}/.claude-plugin/plugin.json')]:
    p = json.load(open(f))
    d = os.path.basename(os.path.dirname(os.path.dirname(f)))
    if p['name'] != d:
        print(f'  ✗ {f}: name "{p["name"]}" ≠ каталог "{d}"'); bad = 1
    if p['name'] not in declared:
        print(f'  ✗ {p["name"]} не оголошений у marketplace.json'); bad = 1
    if p.get('version') != m.get('version'):
        print(f'  ✗ {p["name"]}: версія {p.get("version")} ≠ версії маркетплейсу {m.get("version")}')
        bad = 1
    skills = glob.glob(f'{root}/{d}/skills/*/SKILL.md')
    if not skills:
        print(f'  ✗ {p["name"]}: жодного SKILL.md'); bad = 1

for name in declared:
    if name in ours and not os.path.isfile(f'{root}/{name}/.claude-plugin/plugin.json'):
        print(f'  ✗ у marketplace.json є {name}, а плагіна в plugins/ немає'); bad = 1

total = sum(len(glob.glob(f'{root}/{o}/skills/*/SKILL.md')) for o in ours)
print(f'  плагінів: {len(declared)} · скілів: {total} · версія: {m.get("version")}')
sys.exit(bad)
PY

if command -v claude >/dev/null 2>&1; then
  echo "▸ валідатор Claude Code"
  claude plugin validate . >/dev/null 2>&1 \
    && echo "  маркетплейс: ок" \
    || { echo "  ✗ маркетплейс не пройшов claude plugin validate"; fail=1; }
  for p in $(our_plugin_dirs); do
    claude plugin validate "$p" >/dev/null 2>&1 \
      && echo "  $(basename "$p"): ок" \
      || { echo "  ✗ $(basename "$p") не пройшов claude plugin validate"; fail=1; }
  done
else
  echo "▸ валідатор Claude Code — CLI недоступний, пропущено"
fi

echo
[ "$fail" -eq 0 ] && echo "OK — манифести узгоджені" || { echo "Є порушення" >&2; exit 1; }
