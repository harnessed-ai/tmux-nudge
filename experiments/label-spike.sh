#!/usr/bin/env bash
# label-spike.sh — feasibility spike #2 for tmux-nudge.
#
# blink-spike.sh proved the per-pane border *line* pulses cleanly, but tmux only
# draws borders BETWEEN panes — a single-pane window has no border to pulse.
#
# Question here: can we mark an INDIVIDUAL pane unambiguously, INCLUDING a
# single-pane (no-split) window, using pane-border-status + a per-pane
# pane-border-format label? This is the fallback Layer A cannot cover.
#
# What it does: opens a demo window with a SINGLE full-width pane, turns on a
# per-pane border status line, and pulses a "needs you" label on it.
# Ctrl-C restores and cleans up.
#
# Usage: experiments/label-spike.sh [interval_seconds]
set -euo pipefail

if [ -z "${TMUX:-}" ]; then
  echo "Run this from inside a tmux session." >&2
  exit 1
fi

INTERVAL=${1:-0.6}
COLOR_ON=${NUDGE_ON:-colour214}
COLOR_OFF=${NUDGE_OFF:-colour240}

# Single pane on purpose — this is the case Layer A (border pulse) cannot handle.
win=$(tmux new-window -P -F '#{window_id}' -n nudge-label)
tmux set -w -t "$win" pane-border-status top

tmux display-message "nudge-label: single pane, watch the TOP border label pulse. Ctrl-C to stop."

cleanup() {
  tmux set -w -t "$win" pane-border-status off 2>/dev/null || true
  tmux set -w -t "$win" pane-border-format '#{pane_index} #{pane_title}' 2>/dev/null || true
  tmux kill-window -t "$win" 2>/dev/null || true
}
trap cleanup INT TERM EXIT

on=1
while true; do
  if [ "$on" = 1 ]; then
    fmt=" #[fg=${COLOR_ON},bold]● tmux-nudge — needs you #[default]"; on=0
  else
    fmt=" #[fg=${COLOR_OFF}]○ idle #[default]"; on=1
  fi
  tmux set -w -t "$win" pane-border-format "$fmt"
  tmux refresh-client 2>/dev/null || true
  sleep "$INTERVAL"
done
