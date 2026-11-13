#!/usr/bin/env bash
# tmux-nudge plugin entry point (TPM-compatible).
#
# Install with TPM:
#   set -g @plugin 'harnessed-ai/tmux-nudge'
# then press prefix + I. That's it — this sets up the renderer and, on first
# load, wires the shell + Claude + Kiro integrations for you (idempotent, with
# backups). To skip the auto-wiring:  set -g @nudge-auto-install 'off'
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Renderer + options (reads your @nudge-* config).
"$CURRENT_DIR/bin/nudge" init

# Wire the integrations once. Backgrounded so tmux startup never blocks; a stamp
# file keeps it from re-running on every start. The stamp is versioned: bumping it makes
# existing installs re-run once (v2: move AI agents onto the shared agent-hook.sh).
auto="$(tmux show -gv @nudge-auto-install 2>/dev/null || echo on)"
STAMP="$CURRENT_DIR/.nudge-installed-v2"
if [ "$auto" != "off" ] && [ ! -f "$STAMP" ]; then
  tmux run-shell -b "'$CURRENT_DIR/bin/nudge' install >/dev/null 2>&1 && touch '$STAMP'"
fi
