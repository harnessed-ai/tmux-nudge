#!/usr/bin/env bash
#
# install-integrations.sh — wire tmux-nudge into the AI harnesses + shell.
#
# Idempotent and safe: backs up each file (*.nudge-bak-<ts>) before editing and
# skips anything already wired. Detects what you have (Claude settings, Kiro
# agents, a shell rc) and only touches those. Run directly or via `nudge install`
# (nudge.tmux runs it once automatically on first load).
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NUDGE="$REPO/bin/nudge"
TS="$(date +%Y%m%d-%H%M%S)"

backup() { [ -f "$1" ] && cp "$1" "$1.nudge-bak-$TS" || true; }

# --- shell trigger (zsh/bash) ------------------------------------------------
for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
  [ -f "$rc" ] || continue
  if ! grep -qF "$REPO/shell/nudge.sh" "$rc"; then
    backup "$rc"
    printf '\n# tmux-nudge: nudge a pane when a long command finishes while you'\''re away\nsource %s/shell/nudge.sh\n' "$REPO" >> "$rc"
    echo "  shell: wired into $rc"
  else
    echo "  shell: already wired in $rc"
  fi
done

# --- Claude Code hooks -------------------------------------------------------
CS="$HOME/.claude/settings.json"
if [ -f "$CS" ] && grep -q 'nudge hook' "$CS"; then
  echo "  claude: already wired -> $CS"
elif [ -f "$CS" ]; then
  backup "$CS"
  NUDGE="$NUDGE" python3 - "$CS" <<'PY'
import json, os, sys
p = sys.argv[1]; NUDGE = os.environ["NUDGE"]
d = json.load(open(p)); h = d.setdefault("hooks", {})
def has(entries):
    for e in entries:
        cmds = [x.get("command","") for x in e.get("hooks",[])] if "hooks" in e else [e.get("command","")]
        if any("nudge hook" in c for c in cmds): return True
    return False
def entry(state, matcher="*"):
    return {"matcher": matcher, "hooks": [{"type":"command","command": f"{NUDGE} hook {state}"}]}
changed = False
if not has(h.setdefault("Stop", [])): h["Stop"].append(entry("needs-input")); changed = True
if not has(h.setdefault("Notification", [])): h["Notification"].append(entry("needs-input","permission_prompt|idle_prompt")); changed = True
if not has(h.setdefault("UserPromptSubmit", [])): h["UserPromptSubmit"].append(entry("clear")); changed = True
if changed: json.dump(d, open(p,"w"), indent=2)
print("  claude:", "wired" if changed else "already wired", "->", p)
PY
fi

# --- Kiro CLI hooks (every agent config, skip .example) ----------------------
if [ -d "$HOME/.kiro/agents" ]; then
  for f in "$HOME/.kiro/agents"/*.json; do
    [ -f "$f" ] || continue
    case "$f" in *.example) continue ;; esac
    if grep -q 'nudge hook' "$f"; then echo "  kiro: already wired -> $f"; continue; fi
    backup "$f"
    NUDGE="$NUDGE" python3 - "$f" <<'PY'
import json, os, sys
p = sys.argv[1]; NUDGE = os.environ["NUDGE"]
d = json.load(open(p)); h = d.setdefault("hooks", {})
def has(entries):
    return any("nudge hook" in e.get("command","") for e in entries)
changed = False
if not has(h.setdefault("stop", [])): h["stop"].append({"command": f"{NUDGE} hook needs-input"}); changed = True
if not has(h.setdefault("userPromptSubmit", [])): h["userPromptSubmit"].append({"command": f"{NUDGE} hook clear"}); changed = True
if changed: json.dump(d, open(p,"w"), indent=2)
print("  kiro:", "wired" if changed else "already wired", "->", p)
PY
  done
fi

echo "tmux-nudge integrations installed."
