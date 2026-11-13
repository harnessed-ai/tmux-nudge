#!/usr/bin/env bash
# End-to-end test of tmux-nudge on the shared @agent_* contract, on an isolated tmux
# server with a real attached client; Claude config edits go to a scratch dir and the
# shell rc / Kiro sections run against a scratch $HOME. Never touches your setup.
# Usage: tests/contract_test.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NUDGE="$ROOT/bin/nudge"
HOOK="$ROOT/scripts/agent-hook.sh"
SOCK="nudge-contract-$$"
TMP="$(mktemp -d)"
fail=0

# Sandbox: everything that could touch your config resolves inside $TMP.
export HOME="$TMP/home" CLAUDE_CONFIG_DIR="$TMP/home/.claude" AGENT_HOOK_TOOLS=claude
mkdir -p "$HOME" "$CLAUDE_CONFIG_DIR"
sandboxed() {
	case "$HOME/" in "$TMP"/*) ;; *) return 1 ;; esac
	case "$CLAUDE_CONFIG_DIR/" in "$TMP"/*) ;; *) return 1 ;; esac
}
sandboxed || { echo "refusing to run: not sandboxed"; exit 1; }

t() { command tmux -L "$SOCK" -f /dev/null "$@"; }
CLIENT_PID=""
cleanup() {
	[ -n "$CLIENT_PID" ] && kill "$CLIENT_PID" 2>/dev/null || true
	t kill-server 2>/dev/null || true
	rm -rf "$TMP"
}
trap cleanup EXIT

t new-session -d -s main -n agents -x 120 -y 30
t split-window -t main:agents
t new-window -d -t main -n other
A="$(t display-message -p -t main:agents.0 '#{pane_id}')"   # agent pane (not focused)
B="$(t display-message -p -t main:agents.1 '#{pane_id}')"   # focused pane
O="$(t display-message -p -t main:other '#{pane_id}')"
export TMUX="$(t display-message -p '#{socket_path}'),0,0"
unset NUDGE_SOCKET

opt() { t display-message -p -t "$1" "#{$2}"; }
expect() { # expect <pane> <option> <value> <label>
	local got; got="$(opt "$1" "$2")"
	if [ "$got" = "$3" ]; then echo "  ok   $4"; else echo "  FAIL $4: $2='$got' want '$3'"; fail=1; fi
}
ev() { # ev <pane> <event> [json] — fire agent-hook.sh as Claude would, in that pane
	printf '%s' "${3:-{\}}" | TMUX_PANE="$1" bash "$HOOK" claude "$2"
	sleep 0.5 # listeners run via run-shell -b
}

echo "init:"
"$NUDGE" init
[ "$(t show -gv @agent-on-change-nudge)" = "$NUDGE sync -t" ] && echo "  ok   registers as @agent-on-change listener" ||
	{ echo "  FAIL listener not registered"; fail=1; }
[ "$(t show -gv @agent-hook-provider-nudge)" = "$HOOK" ] && echo "  ok   advertises its agent-hook copy" ||
	{ echo "  FAIL provider not advertised"; fail=1; }

echo "agent state drives the nudge (one hook, no 'nudge hook'):"
ev "$A" SessionStart
expect "$A" @nudge_state "" "idle agent: no nudge"
ev "$A" PermissionRequest
expect "$A" @nudge_state needs-input "waiting (permission) → orange needs-input"
ev "$A" PostToolUse
expect "$A" @nudge_state "" "busy again → nudge cleared"
ev "$A" Stop
expect "$A" @nudge_state done "finished turn → green done"
ev "$A" UserPromptSubmit
expect "$A" @nudge_state "" "you replied → cleared"
ev "$A" StopFailure
expect "$A" @nudge_state error "failed turn → red error"
ev "$A" SessionEnd
expect "$A" @nudge_state "" "agent exits → cleared"

echo "seen (shared with other plugins):"
ev "$A" Stop
bash "$HOOK" --seen "$A"; sleep 0.5      # what another plugin does when it sees you look
expect "$A" @agent_state idle "another plugin marking it seen → idle"
expect "$A" @nudge_state "" "… and nudge's label clears too"

# A real client, so the daemon's focus auto-clear can see what you're looking at.
python3 -I - "$SOCK" <<'PY' &
import os, pty, sys, time, fcntl, termios, struct
pid, fd = pty.fork()
if pid == 0:
    os.environ["TERM"] = "xterm-256color"
    os.execvp("tmux", ["tmux", "-L", sys.argv[1], "attach", "-t", "main:other"])
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 120, 0, 0))
end = time.time() + 60
while time.time() < end:
    try: os.read(fd, 65536)
    except OSError: break
PY
CLIENT_PID=$!
sleep 1.2
ev "$A" Stop
expect "$A" @nudge_state done "done while you're in another window: nudged"
t select-window -t main:agents; t select-pane -t "$A"; sleep 1.5
expect "$A" @agent_state idle "focusing it → seen in the shared state (idle)"
expect "$A" @nudge_state "" "… and the label is gone"
t select-window -t main:other; sleep 0.3
ev "$A" PermissionRequest
t select-window -t main:agents; t select-pane -t "$A"; sleep 1.5
expect "$A" @nudge_state "" "focusing a waiting agent dismisses the label"
expect "$A" @agent_state blocked "… but it stays waiting (still needs you)"
t select-window -t main:other; sleep 0.3

echo "shell commands:"
"$NUDGE" shell-done -t "$B" -s done -n "npm test"
expect "$B" @agent_tool shell "a long command, finished while away → a shell row"
expect "$B" @agent_name "npm test" "… named after the command"
expect "$B" @nudge_state done "… and nudged"
"$NUDGE" shell-start -t "$B"
expect "$B" @agent_state "" "next command in that pane → row cleared"
expect "$B" @nudge_state "" "… and nudge cleared"
"$NUDGE" shell-done -t "$O" -s error -n "make"
expect "$O" @agent_state "" "finished while you're watching it → nothing to report"
"$NUDGE" shell-done -t "$B" -s done -n "sleep 20"
bash "$HOOK" --seen "$B"; sleep 0.4
expect "$B" @agent_tool "" "a seen shell row disappears (no idle leftovers)"

echo "install migrates old hooks (scratch config):"
sandboxed || { echo "refusing to install: not sandboxed"; exit 1; }
cat > "$CLAUDE_CONFIG_DIR/settings.json" <<JSON
{"hooks": {
  "Stop": [{"matcher":"*","hooks":[{"type":"command","command":"/old/tmux-nudge/bin/nudge hook needs-input"}]},
           {"hooks":[{"type":"command","command":"my-own-hook"}]}],
  "UserPromptSubmit": [{"matcher":"*","hooks":[{"type":"command","command":"/old/tmux-nudge/bin/nudge hook clear"}]}]
}}
JSON
bash "$ROOT/scripts/install-integrations.sh" >/dev/null
cfg="$CLAUDE_CONFIG_DIR/settings.json"
[ "$(jq '[.. | strings | select(contains("nudge hook"))] | length' "$cfg")" = 0 ] &&
	echo "  ok   old 'nudge hook' entries removed" || { echo "  FAIL legacy hooks left"; fail=1; }
[ "$(jq '[.hooks[] | map(.hooks[] | select(.command | contains("agent-hook.sh"))) | length] | max' "$cfg")" = 1 ] &&
	[ "$(jq '.hooks | keys | length' "$cfg")" -ge 8 ] &&
	echo "  ok   shared hook registered once per event" || { echo "  FAIL shared hook not registered once"; fail=1; }
jq -e '[.. | strings] | index("my-own-hook")' "$cfg" >/dev/null &&
	echo "  ok   your own hooks kept" || { echo "  FAIL user hook lost"; fail=1; }

echo "uninstall hands the hook to another loaded plugin:"
mkdir -p "$TMP/sibling"
sed '2s/.*/# agent-hook-version: 3/' "$HOOK" > "$TMP/sibling/agent-hook.sh"
t set -g @agent-hook-provider-sibling "$TMP/sibling/agent-hook.sh"
sandboxed || { echo "refusing to uninstall: not sandboxed"; exit 1; }
"$NUDGE" uninstall >/dev/null
reg="$(jq -r '[.. | strings | select(contains("agent-hook.sh"))][0]' "$cfg")"
[[ "$reg" == *"$TMP/sibling/agent-hook.sh"* ]] && echo "  ok   hook re-pointed to the other plugin's copy" ||
	{ echo "  FAIL hook not handed over: $reg"; fail=1; }
[ -z "$(t show -gqv @agent-on-change-nudge)" ] && echo "  ok   listener unregistered" || { echo "  FAIL listener left"; fail=1; }

[ "$fail" = 0 ] && echo "PASS" || { echo "FAILED"; exit 1; }
