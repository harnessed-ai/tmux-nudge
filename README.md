# tmux-nudge

A tmux plugin that **nudges you when a pane needs a human** — by blinking a label
on the pane and its entry in the status bar. Anything can nudge you: a finished
shell script, an idle build, or an AI coding agent waiting for your response.

## Why

Existing tools split the problem in two and solve neither completely:

- **Generic completion notifiers** (`monitor-silence`, `tmux-notify`, `noti`,
  `undistract-me`) only know "the process stopped." They can't tell *done* from
  *waiting for input*, and modern AI-agent TUIs redraw constantly, so silence/
  activity monitoring misfires on them.
- **AI-agent indicators** (e.g. `tmux-agent-indicator`) read agent hooks and get
  precise state, but are AI-only, use **static** border colours, and can't style
  individual (non-active) panes independently.

`tmux-nudge` unifies both behind **one renderer**: pluggable trigger sources feed
a single "make this pane demand attention" engine, so the visual treatment is
identical no matter what triggered it — shell, script, or AI.

## How it works

Pluggable **trigger sources** feed one **renderer**, so the signal is identical
no matter what flagged the pane:

| Trigger          | Source                                   | Covers                                 |
| ---------------- | ---------------------------------------- | -------------------------------------- |
| AI harness hook  | `nudge hook` from Claude Code / Codex / … | AI agents (needs-input / done / error) |
| Shell completion | `shell/nudge.sh` precmd (zsh/bash)        | any long-running command               |
| Manual / scripts | `nudge on`                                | anything                               |

A flagged pane is marked two ways, both **per-pane** (no shared-border ambiguity):

- a **blinking label** on the pane's own border row (`● tmux-nudge — needs you`)
- the pane's **window entry blinks** in the status bar — but only while that
  window is **not** the one you're currently on

A small daemon animates the blink and **auto-clears** any flagged pane the moment
you view it (mouse, keyboard, or window switch alike). It starts on the first
nudge and exits when none remain.

## Status

Working end to end on tmux 3.6b: engine + renderer, AI-harness hooks (Claude
Code, Codex), the generic shell trigger, and safe install/uninstall.

### Try it live (isolated — won't touch your real session)

```sh
# from a PLAIN terminal (not inside tmux):
experiments/try-engine.sh
# … watch the flagged pane's label blink and its window entry blink; C-b d, then:
tmux -L nudgedemo kill-server
```

### CLI

```sh
nudge init                      # install (done by nudge.tmux); saves your config
nudge uninstall                 # fully reverse init; restores your config
nudge on  [-t pane] [-s state]  # state: needs-input | done | error
nudge off [-t pane]
nudge status
```

`init` is non-destructive: it saves your `pane-border-format` and composes with
it (non-nudging panes keep your look), and installs **no** tmux hooks — auto-clear
is daemon-driven. `uninstall` restores your format exactly (and strips any focus
hooks left by older versions, leaving your own untouched).

### As a plugin (TPM)

```tmux
set -g @plugin 'bmohan01/tmux-nudge'
```

## AI harness integration

Any terminal AI harness that can run a command on a lifecycle event can drive
tmux-nudge — the integration point is a single, harness-neutral command:

```sh
nudge hook <needs-input|done|error|clear>
```

It finds the agent's pane from `$TMUX_PANE`, ignores any payload the harness
appends (JSON on stdin or argv), and **never exits non-zero** (a failing Claude
`Stop` hook would otherwise block Claude). Focusing the pane also auto-clears it.

Adding a harness = pointing its event config at `nudge hook <state>`. No new
code. Config generators print ready-to-paste snippets with absolute paths:

**Claude Code** — `nudge claude-config` → `~/.claude/settings.json`

| Claude event | Fires when | → |
| --- | --- | --- |
| `Stop` | Claude finishes a turn | `needs-input` |
| `Notification` (`permission_prompt`\|`idle_prompt`) | Claude blocked/waiting | `needs-input` |
| `UserPromptSubmit` | you send a prompt | `clear` |

**Codex (OpenAI)** — `nudge codex-config` → `~/.codex/config.toml`
(Codex emits `agent-turn-complete` → `needs-input`; clears on focus.)

**Any other harness** (Kiro CLI, aider, gemini-cli, opencode, …): register a
shell command / hook that runs `<path>/bin/nudge hook needs-input` on
turn-complete (and `… clear` on prompt-submit, if the harness exposes it).
This applies to CLI harnesses running **inside tmux**; a GUI IDE not in a tmux
pane is out of scope.

## Any long-running command (generic)

Not just AI — get nudged when *any* foreground command finishes (builds, tests,
`ssh`, scripts). Enable the shell integration in `~/.zshrc` or `~/.bashrc`:

```sh
eval "$(/path/to/tmux-nudge/bin/nudge shell-init)"
# or: source /path/to/tmux-nudge/shell/nudge.sh
```

When a command runs longer than `$NUDGE_MIN_SECONDS` (default 15) it nudges its
pane on completion — **success → done (green), failure → error (red)** — but
only if you've **switched away** from that pane (`--if-away`), so it never nags
a pane you're watching. Focus the pane to clear it.

### Feasibility spikes

Throwaway demos from early feasibility work:
[`experiments/blink-spike.sh`](experiments/blink-spike.sh) (per-pane border
colour — since dropped, as it colours the shared divider) and
[`experiments/label-spike.sh`](experiments/label-spike.sh) (single-pane label —
the approach that shipped).

## License

MIT
