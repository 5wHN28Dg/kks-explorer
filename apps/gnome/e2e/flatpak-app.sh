#!/bin/sh
# Run the installed Flatpak like the test runs the plain binary: test_gnome.py passes its settings as KKS_* variables
# and keeps the app's files in /tmp, so both go into the sandbox. When the test ends this script, it stops its own
# instance (ending `flatpak run` alone leaves the sandbox running).
#   python3 apps/gnome/e2e/test_gnome.py "$PWD/apps/gnome/e2e/flatpak-app.sh"
args=""
for v in $(env | grep '^KKS_' | cut -d= -f1); do
  args="$args --env=$v=$(printenv "$v")"
done
# shellcheck disable=SC2086
flatpak run --filesystem=/tmp $args io.github._5wHN28Dg.kks_explorer &
child=$!
stop() {
  inst=$(flatpak ps --columns=instance,pid | awk -v p="$child" '$2 == p { print $1 }')
  [ -n "$inst" ] && flatpak kill "$inst"
  kill "$child" 2>/dev/null
  exit 0
}
# the test's SIGUSR1/SIGUSR2 (screenshot, scroll to a figure) go to the app inside the sandbox
forward() {
  sandbox=$(flatpak ps --columns=pid,child-pid | awk -v p="$child" '$1 == p { print $2 }')
  [ -z "$sandbox" ] && return
  # the app is a descendant of the sandbox's first process (bwrap): the one running kks-explorer
  todo="$sandbox"
  while [ -n "$todo" ]; do
    next=""
    for p in $todo; do
      case "$(tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null)" in
        kks-explorer*|/app/bin/kks-explorer*) kill -s "$1" "$p"; return ;;
      esac
      next="$next $(pgrep -P "$p" | tr '\n' ' ')"
    done
    todo=$(echo $next)
  done
}
trap stop TERM INT
trap 'forward USR1' USR1
trap 'forward USR2' USR2
# `wait` returns early when a trapped signal arrives: wait again until flatpak run itself ends
while kill -0 "$child" 2>/dev/null; do wait "$child"; done
