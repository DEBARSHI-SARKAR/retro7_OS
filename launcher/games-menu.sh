#!/bin/sh
# retro7 launcher: xmenu list built from ~/.config/games.list
# entries are "Name::command"; "#" lines are comments

LIST="$HOME/.config/games.list"
[ -f "$LIST" ] || { echo "retro7: no $LIST" >&2; exit 1; }

ITEMS=""
while IFS= read -r line; do
  case "$line" in ""|'#'*) continue ;; esac
  name=${line%%::*}
  [ -n "$name" ] && ITEMS="$ITEMS $name"
done < "$LIST"
[ -n "$ITEMS" ] || ITEMS="no-games-configured"

while :; do
  pick=$(xmenu 2>/dev/null $ITEMS) || exit 0
  [ -n "$pick" ] || continue
  while IFS= read -r line; do
    case "$line" in ""|'#'*) continue ;; esac
    name=${line%%::*}; cmd=${line#*::}
    if [ "$pick" = "$name" ] && [ -n "$cmd" ]; then
      sh -c "$cmd" &
      break
    fi
  done < "$LIST"
done
