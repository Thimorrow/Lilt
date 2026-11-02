#!/bin/sh
# Forwards a finished coding-agent turn to Lilt's notch. Never fails or delays the agent.
#   Claude Code Stop hook:  agent-hook.sh claude                              (hook JSON on stdin)
#   Codex notify:           agent-hook.sh codex [previous notify command…]   (Codex appends its JSON)
# LILT_BIN overrides the Lilt executable; LILT_DATA_DIR targets an isolated instance.
agent="$1"
[ $# -gt 0 ] && shift
bin="${LILT_BIN:-}"
for candidate in "$(dirname "$0")/../build/Lilt.app/Contents/MacOS/Lilt" "/Applications/Lilt.app/Contents/MacOS/Lilt"; do
  [ -z "$bin" ] && [ -x "$candidate" ] && bin="$candidate"
done
# Older Lilt builds do not know --notify and would start a second app instead.
supported=0
[ -n "$bin" ] && [ -x "$bin" ] && grep -qa 'lilt-agent-inbox-' "$bin" && supported=1
notify() {
  if [ -n "${LILT_DATA_DIR:-}" ]; then "$bin" --notify "$@" --data-dir "$LILT_DATA_DIR"; else "$bin" --notify "$@"; fi
}
case "$agent" in
  claude)
    if [ "$supported" = 1 ]; then notify claude >/dev/null 2>&1; else cat >/dev/null; fi
    ;;
  codex)
    json=""
    for json; do :; done
    [ "$supported" = 1 ] && notify codex "$json" >/dev/null 2>&1
    # Keep the notify command configured before Lilt; Codex's JSON is already its last argument.
    [ $# -gt 1 ] && exec "$@"
    ;;
esac
exit 0
