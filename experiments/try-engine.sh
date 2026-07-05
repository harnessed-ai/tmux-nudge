#!/usr/bin/env bash
# try-engine.sh — watch the full tmux-nudge engine live, in a throwaway server.
#
# Runs on an isolated socket (NUDGE_SOCKET=nudgedemo) so it CANNOT touch your
# real tmux session or config. Run it from a PLAIN terminal (NOT inside tmux,
# to avoid a nested-session warning).
#
#   experiments/try-engine.sh
#
# Then:
#   - Window 1 "split": the LEFT pane border pulses orange + a "needs you"
#     label. Switch INTO the left pane (C-b Left) — it auto-clears on focus.
#   - Window 2 "single": one full pane with a green "done" label — proves the
#     single-pane case that has no border to pulse. (C-b 2 to view it.)
#   - Detach with C-b d, then clean up:  tmux -L nudgedemo kill-server
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
export NUDGE_SOCKET=nudgedemo
NUDGE="$HERE/bin/nudge"
T() { command tmux -L "$NUDGE_SOCKET" "$@"; }

if [ -n "${TMUX:-}" ]; then
  echo "Please run this from a plain terminal, not inside tmux." >&2
  exit 1
fi

T kill-server 2>/dev/null || true

# Window 1: two panes, nudge the LEFT one (RIGHT stays active so it won't
# instantly auto-clear on attach).
T new-session -d -s demo -x 220 -y 55 -n split
T split-window -h -t demo:split
"$NUDGE" init
LEFT="$(T list-panes -t demo:split -F '#{pane_id}' | head -1)"
"$NUDGE" on -t "$LEFT" -s needs-input

# Window 2: a single unsplit pane, nudged "done" (green). Not the active window,
# so its lone pane isn't focused yet and the nudge persists until you view it.
T new-window -t demo -n single
SINGLE="$(T list-panes -t demo:single -F '#{pane_id}' | head -1)"
"$NUDGE" on -t "$SINGLE" -s done

T select-window -t demo:split
echo "Attaching… (C-b d to detach, then: tmux -L $NUDGE_SOCKET kill-server)"
exec command tmux -L "$NUDGE_SOCKET" attach -t demo
