#!/usr/bin/env bash
# Перевіряє, що жодну копію в references/ не правили руками.
set -euo pipefail
export LC_ALL=C.utf8   # без цього grep працює в байтовому режимі і кириличні діапазони [иу] не збігаються
cd "$(dirname "$0")/.."

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cp -a plugins "$tmp/before"
./scripts/sync-shared.sh > /dev/null

if diff -rq "$tmp/before" plugins > "$tmp/diff" 2>&1; then
  echo "OK — спільні контракти синхронні"
else
  echo "РОЗХОДЖЕННЯ: копію правили руками замість shared/" >&2
  cat "$tmp/diff" >&2
  rm -rf plugins && cp -a "$tmp/before" plugins
  exit 1
fi
