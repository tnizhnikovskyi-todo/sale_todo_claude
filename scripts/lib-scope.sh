# Межа дії перевірок: тільки плагіни з scripts/our-plugins.txt.
# Підключати після `cd` у корінь репозиторію: `. scripts/lib-scope.sh`
PLUGDIR="${PLUGDIR:-plugins}"

ours () {  # назви наших плагінів, по одній на рядок
  sed 's/#.*//' scripts/our-plugins.txt | sed '/^[[:space:]]*$/d'
}

our_plugin_dirs () {
  for p in $(ours); do [ -d "$PLUGDIR/$p" ] && echo "$PLUGDIR/$p"; done
}

our_skill_files () {  # шляхи до SKILL.md наших плагінів
  for p in $(ours); do
    for f in "$PLUGDIR/$p"/skills/*/SKILL.md; do [ -e "$f" ] && echo "$f"; done
  done
}

# Дві перевірки — джерельні за призначенням: вони звіряють манифест маркетплейсу
# ЦЬОГО репозиторію. Після переносу фаза лежить підкаталогом у чужому репозиторії,
# де ні цього манифесту, ні git-кореня немає — і приймання переїжджає на бік цілі.
# Тому такі скрипти не падають і не брешуть, а свідомо пропускаються.
#
#   Вжиток першим рядком після `. ./scripts/lib-scope.sh`:
#     source_repo_or_skip "перевірка установки"
source_repo_or_skip () {
  what="${1:-ця перевірка}"
  if [ ! -f .claude-plugin/marketplace.json ]; then
    echo "▸ $what — пропущено: тут немає .claude-plugin/marketplace.json."
    echo "  Це не репозиторій-джерело фази, а її копія в чужому дереві."
    echo "  Приймання установки робиться на боці маркетплейсу, з якого ставлять."
    exit 0
  fi
  if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
    echo "▸ $what — пропущено: каталог не є git-репозиторієм."
    exit 0
  fi
}
