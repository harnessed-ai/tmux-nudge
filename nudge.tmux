#!/usr/bin/env bash
# tmux-nudge plugin entry point (TPM-compatible).
# Add to ~/.tmux.conf:  set -g @plugin 'bmohan01/tmux-nudge'
# Then reload tmux. This installs the global formats and focus hook.
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$CURRENT_DIR/bin/nudge" init
