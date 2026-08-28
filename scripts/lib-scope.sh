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
