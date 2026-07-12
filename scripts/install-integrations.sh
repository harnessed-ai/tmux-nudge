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

# --- Claude Code hooks -------------------------------------------------------
CS="$HOME/.claude/settings.json"
if [ -f "$CS" ]; then
  python3 - "$CS" <<'PY'
import json, os, sys, shutil
p = sys.argv[1]; NUDGE = os.environ["NUDGE"]; TS = os.environ["TS"]
d = json.load(open(p)); h = d.setdefault("hooks", {})
def is_ours(e):
    cmds = [x.get("command","") for x in e.get("hooks",[])] if "hooks" in e else [e.get("command","")]
    return any("nudge hook" in c for c in cmds)
def entry(state, matcher):
    return {"matcher": matcher, "hooks": [{"type":"command","command": f"{NUDGE} hook {state}"}]}
want = {"Stop":("needs-input","*"),
        "Notification":("needs-input","permission_prompt|idle_prompt"),
        "UserPromptSubmit":("clear","*")}
before = json.dumps(d, sort_keys=True)
for ev,(state,matcher) in want.items():
    arr = h.setdefault(ev, [])
    arr[:] = [e for e in arr if not is_ours(e)]   # drop ours (repairs stale paths)
    arr.append(entry(state, matcher))
after = json.dumps(d, sort_keys=True)
if before != after:
    shutil.copy(p, f"{p}.nudge-bak-{TS}")
    json.dump(d, open(p,"w"), indent=2)
    print("  claude: wired/repaired ->", p)
else:
    print("  claude: already correct ->", p)
PY
fi

# --- Kiro CLI hooks (every agent config, skip .example) ----------------------
if [ -d "$HOME/.kiro/agents" ]; then
  for f in "$HOME/.kiro/agents"/*.json; do
    [ -f "$f" ] || continue
    case "$f" in *.example) continue ;; esac
    python3 - "$f" <<'PY'
import json, os, sys, shutil
p = sys.argv[1]; NUDGE = os.environ["NUDGE"]; TS = os.environ["TS"]
d = json.load(open(p)); h = d.setdefault("hooks", {})
def is_ours(e): return "nudge hook" in e.get("command","")
want = {"stop":"needs-input", "userPromptSubmit":"clear"}
before = json.dumps(d, sort_keys=True)
for ev,state in want.items():
    arr = h.setdefault(ev, [])
    arr[:] = [e for e in arr if not is_ours(e)]
    arr.append({"command": f"{NUDGE} hook {state}"})
after = json.dumps(d, sort_keys=True)
if before != after:
    shutil.copy(p, f"{p}.nudge-bak-{TS}")
    json.dump(d, open(p,"w"), indent=2)
    print("  kiro: wired/repaired ->", p)
else:
    print("  kiro: already correct ->", p)
PY
  done
fi

echo "tmux-nudge integrations installed (pointing at $REPO)."
