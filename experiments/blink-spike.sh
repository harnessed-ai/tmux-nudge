#!/usr/bin/env bash
# blink-spike.sh — feasibility spike for tmux-nudge.
#
# Question we are answering: can tmux animate a SINGLE pane's border
# (a smooth blink/pulse), independently of other panes, without jank?
#
# What it does: opens a demo window with two side-by-side panes and pulses
# the LEFT pane's border between an "attention" colour and a dim colour on a
# timer. Watch it. Ctrl-C (in the pane running this) restores and cleans up.
#
# Usage:
#   experiments/blink-spike.sh [interval_seconds]
#   NUDGE_ON=colour214 NUDGE_OFF=colour240 experiments/blink-spike.sh 0.4
set -euo pipefail

if [ -z "${TMUX:-}" ]; then
  echo "Run this from inside a tmux session." >&2
  exit 1
fi

INTERVAL=${1:-0.5}                 # seconds between toggles
COLOR_ON=${NUDGE_ON:-colour214}    # attention (orange)
COLOR_OFF=${NUDGE_OFF:-colour240}  # idle (dim grey)

# Demo window with a vertical split so there is a border to colour.
win=$(tmux new-window -P -F '#{window_id}' -n nudge-spike)
tmux split-window -h -t "$win"
# Target the LEFT pane; keep the RIGHT pane active so we can also see how the
# shared border between an active and inactive pane resolves.
target=$(tmux list-panes -t "$win" -F '#{pane_id}' | head -1)
tmux select-pane -t "$(tmux list-panes -t "$win" -F '#{pane_id}' | tail -1)"

tmux display-message "nudge-spike: watch the LEFT pane border pulse. Ctrl-C to stop."

cleanup() {
  tmux set -p -t "$target" pane-border-style default 2>/dev/null || true
  tmux set -p -t "$target" pane-active-border-style default 2>/dev/null || true
  tmux kill-window -t "$win" 2>/dev/null || true
}
trap cleanup INT TERM EXIT

on=1
while true; do
  if [ "$on" = 1 ]; then
    style="fg=${COLOR_ON},bold"; on=0
  else
    style="fg=${COLOR_OFF}"; on=1
  fi
  # Set both so it works whether the pane is active or not.
  tmux set -p -t "$target" pane-border-style "$style"
  tmux set -p -t "$target" pane-active-border-style "$style"
  tmux refresh-client 2>/dev/null || true
  sleep "$INTERVAL"
done
