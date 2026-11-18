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
export XDG_DATA_HOME="$TMP/home/.local/share" XDG_CONFIG_HOME="$TMP/home/.config" CODEX_HOME="$TMP/home/.codex"
unset AGENT_HOOK_HOME OPENCODE_CONFIG_DIR
mkdir -p "$HOME" "$CLAUDE_CONFIG_DIR"
sandboxed() {
	case "$HOME/" in "$TMP"/*) ;; *) return 1 ;; esac
	case "$CLAUDE_CONFIG_DIR/" in "$TMP"/*) ;; *) return 1 ;; esac
	case "$XDG_DATA_HOME/$XDG_CONFIG_HOME/$CODEX_HOME/" in "$TMP"/*) ;; *) return 1 ;; esac
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
t set -g window-status-format " #I:#W "
"$NUDGE" init; "$NUDGE" init
[ "$(t show -gv window-status-format)" = ' #I:#W#{?#{@nudge_wglyph}, #{@nudge_wglyph},} ' ] &&
	echo "  ok   badge token added to window-status-format once, before its trailing space" ||
	{ echo "  FAIL window-status-format: $(t show -gv window-status-format)"; fail=1; }
[ "$(t show -gv @agent-on-change-nudge)" = "$NUDGE sync -t" ] && echo "  ok   registers as @agent-on-change listener" ||
	{ echo "  FAIL listener not registered"; fail=1; }
[ "$(t show -gv @agent-hook-provider-nudge)" = "$HOOK" ] && echo "  ok   advertises its agent-hook copy" ||
	{ echo "  FAIL provider not advertised"; fail=1; }

echo "agent state drives the nudge (one hook, no 'nudge hook'):"
ev "$A" SessionStart
expect "$A" @nudge_state "" "idle agent: no nudge"
ev "$A" PermissionRequest
expect "$A" @nudge_state needs-input "waiting (permission) → orange needs-input"
t set -p -t "$A" @agent_name fifo; "$NUDGE" sync -t "$A"
expect "$A" @nudge_label "● waiting · fifo" "label names the agent, no plugin prefix"
AW="$(t display-message -p -t "$A" '#{window_id}')"
wopt() { t show -wqv -t "$AW" "$1"; }
[ "$(wopt @nudge_wglyph)" = "●" ] && [ "$(wopt @nudge_wcolor)" = colour214 ] &&
	echo "  ok   its window entry gets the ● badge in orange" || { echo "  FAIL badge: '$(wopt @nudge_wglyph)' '$(wopt @nudge_wcolor)'"; fail=1; }
t set -p -t "$A" @agent_activity "Bash: npm test"; "$NUDGE" sync -t "$A"
expect "$A" @nudge_label "● waiting · fifo · Bash: npm test" "… and what it's waiting on"
ev "$A" PostToolUse
expect "$A" @nudge_state "" "busy again → nudge cleared"
[ -z "$(wopt @nudge_wglyph)" ] && echo "  ok   … and the window badge with it" || { echo "  FAIL badge left: '$(wopt @nudge_wglyph)'"; fail=1; }
ev "$A" Stop
expect "$A" @nudge_state done "finished turn → green done"
expect "$A" @nudge_label "✓ done · fifo" "done label"
t set -g @nudge-label-done "finished!"; "$NUDGE" sync -t "$A"
expect "$A" @nudge_label "finished!" "your own @nudge-label-done wins"
t set -gu @nudge-label-done
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

echo "elsewhere chip and prefix + g:"
case "$(t show -gv status-right)" in '#{E:@nudge_elsewhere}'*) echo "  ok   chip token prepended to status-right" ;;
	*) echo "  FAIL status-right: $(t show -gv status-right)"; fail=1 ;; esac
t list-keys -T prefix | grep -q "nudge' next" && echo "  ok   prefix + g bound" || { echo "  FAIL jump key not bound"; fail=1; }
t new-session -d -s far -n build
F="$(t display-message -p -t far:build '#{pane_id}')"
t set -p -t "$F" @agent_tool claude
ev "$F" PermissionRequest
t set -p -t "$F" @agent_state_since 1; "$NUDGE" elsewhere   # the oldest one waiting
chip() { t show -qv -t "$1" @nudge_elsewhere; }
case "$(chip main)" in *"far:"*build*) echo "  ok   main shows the agent waiting in far" ;; *) echo "  FAIL main chip: '$(chip main)'"; fail=1 ;; esac
case "$(chip far)" in *"main:"*) echo "  ok   far shows main's waiting agent, not its own" ;; *) echo "  FAIL far chip: '$(chip far)'"; fail=1 ;; esac
CL="$(t list-clients -F '#{client_name}' | head -1)"
here() { t list-clients -F '#{pane_id}' | head -1; }   # the client's pane (display -c resolves elsewhere)
"$NUDGE" next -c "$CL" -p "$(here)"; sleep 0.3
[ "$(here)" = "$F" ] && echo "  ok   next: jumps across sessions to the oldest waiting agent" ||
	{ echo "  FAIL next went to $(here)"; fail=1; }
"$NUDGE" next -c "$CL" -p "$F"; sleep 0.3
[ "$(here)" = "$A" ] && echo "  ok   next again: moves on to the next one" ||
	{ echo "  FAIL second next went to $(here)"; fail=1; }
ev "$F" UserPromptSubmit
[ -z "$(chip main)" ] && echo "  ok   answered → chip gone" || { echo "  FAIL chip left: '$(chip main)'"; fail=1; }
t switch-client -c "$CL" -t main:other; t kill-session -t far; sleep 0.3

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

echo "uninstall:"
SH="$XDG_DATA_HOME/harnessed-ai/agent-hook.sh"
[ -x "$SH" ] && [ -z "$(jq -r '[.. | strings | select(contains("agent-hook.sh"))] | map(select(contains($sh) | not)) | .[]' --arg sh "$SH" "$cfg")" ] &&
	echo "  ok   install put the hook at the shared fixed path and registered that" || { echo "  FAIL not at the fixed path"; fail=1; }
t set -g @agent-hook-provider-sibling x            # another plugin still using the hook
sandboxed || { echo "refusing to uninstall: not sandboxed"; exit 1; }
"$NUDGE" uninstall >/dev/null
[ "$(jq '[.. | strings | select(contains("agent-hook.sh"))] | length' "$cfg")" = 8 ] && [ -x "$SH" ] &&
	echo "  ok   another plugin still uses it: hook left in place" || { echo "  FAIL hook removed while in use"; fail=1; }
[ -z "$(t show -gqv @agent-on-change-nudge)" ] && echo "  ok   listener unregistered" || { echo "  FAIL listener left"; fail=1; }
[ "$(t show -gv window-status-format)" = " #I:#W " ] && echo "  ok   window-status-format restored" ||
	{ echo "  FAIL window-status-format: $(t show -gv window-status-format)"; fail=1; }
t set -gu @agent-hook-provider-sibling
"$NUDGE" init; env -u AGENT_HOOK_TOOLS "$NUDGE" uninstall >/dev/null   # nudge is the last one using it
[ "$(jq '[.. | strings | select(contains("agent-hook.sh"))] | length' "$cfg")" = 0 ] && [ ! -e "$SH" ] &&
	echo "  ok   last plugin out: hook unregistered and removed" || { echo "  FAIL hook left behind"; fail=1; }

[ "$fail" = 0 ] && echo "PASS" || { echo "FAILED"; exit 1; }
