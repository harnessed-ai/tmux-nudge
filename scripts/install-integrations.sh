#!/usr/bin/env bash
#
# install-integrations.sh — wire tmux-nudge into the AI harnesses + shell.
#
# Idempotent AND path-repairing: it makes every integration point at THIS
# checkout's bin/nudge, so it's safe to run repeatedly and it seamlessly fixes
# things up if the repo moved (e.g. you switched from a local clone to the TPM
# install, or moved the folder). Backs up each file before changing it
# (*.nudge-bak-<ts>), only when it actually changes something, and appends to
# your existing hooks rather than overwriting them.
#
# Run directly or via `nudge install` (nudge.tmux runs it once on first load).
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NUDGE="$REPO/bin/nudge"
export NUDGE TS
TS="$(date +%Y%m%d-%H%M%S)"

# --- shell trigger (zsh/bash): ensure exactly one source line, correct path ---
SRC="source $REPO/shell/nudge.sh"
for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
  [ -f "$rc" ] || continue
  if grep -qF "$SRC" "$rc"; then
    echo "  shell: already correct -> $rc"
  elif grep -qE 'source .*/shell/nudge\.sh' "$rc"; then
    cp "$rc" "$rc.nudge-bak-$TS"
    tmp="$(mktemp)"; sed -E "s#source .*/shell/nudge\.sh#${SRC}#" "$rc" > "$tmp" && mv "$tmp" "$rc"
    echo "  shell: repaired path -> $rc"
  else
    cp "$rc" "$rc.nudge-bak-$TS"
    printf '\n# tmux-nudge: nudge a pane when a long command finishes while you'\''re away\n%s\n' "$SRC" >> "$rc"
    echo "  shell: wired -> $rc"
  fi
done

# --- AI agents (Claude Code, Kiro CLI) ---------------------------------------
# Agents report through the shared harnessed-ai hook (scripts/agent-hook.sh), which
# writes the pane's @agent_state; nudge just renders it (see `nudge sync`). Other plugins
# can share the same hook, so with several installed each agent event runs ONE hook.
# 1) drop the hooks older tmux-nudge versions installed ("nudge hook …"; Codex's notify
#    line in ~/.codex/config.toml is separate and stays);
# 2) register the shared hook: one entry per event, keeping a newer copy if a sibling
#    plugin already registered one.
if command -v jq >/dev/null 2>&1; then
  python3 - "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json" "$HOME"/.kiro/agents/*.json <<'PY'
import json, os, sys, shutil
TS = os.environ["TS"]
def legacy(c): return "nudge hook" in (c or "")
for p in sys.argv[1:]:
    if not os.path.isfile(p) or p.endswith(".example"):
        continue
    try:
        d = json.load(open(p))
    except Exception:
        continue
    h = d.get("hooks")
    if not isinstance(h, dict):
        continue
    before = json.dumps(d, sort_keys=True)
    for ev, arr in list(h.items()):
        if not isinstance(arr, list):
            continue
        keep = []
        for e in arr:
            if isinstance(e, dict) and isinstance(e.get("hooks"), list):     # Claude
                e["hooks"] = [x for x in e["hooks"] if not legacy(x.get("command"))]
                if e["hooks"]:
                    keep.append(e)
            elif not (isinstance(e, dict) and legacy(e.get("command"))):     # Kiro
                keep.append(e)
        h[ev] = keep
    if json.dumps(d, sort_keys=True) != before:
        shutil.copy(p, f"{p}.nudge-bak-{TS}")
        json.dump(d, open(p, "w"), indent=2)
        print("  agents: removed old 'nudge hook' entries ->", p)
PY
  bash "$REPO/scripts/install-hooks.sh" 2>&1 | sed 's/^/  agents: /'
else
  echo "  agents: jq not found — skipping agent hooks (brew install jq, then: nudge install)"
fi

# Codex now reports through the shared agent hook (~/.codex/hooks.json, above). An older
# hand-pasted `notify = [".../nudge", "hook", ...]` line would nudge a second time, in the
# wrong colour; it's your file, so just point it out.
codex_toml="${CODEX_HOME:-$HOME/.codex}/config.toml"
if [ -f "$codex_toml" ] && grep -qE '^[[:space:]]*notify[[:space:]]*=.*nudge.*hook' "$codex_toml"; then
  echo "  codex: remove the old 'notify = [... nudge hook ...]' line from $codex_toml —"
  echo "         Codex now reports through the shared agent hook (approve it once in /hooks)."
fi

echo "tmux-nudge integrations installed (pointing at $REPO)."
