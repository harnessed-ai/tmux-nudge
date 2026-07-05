# tmux-nudge

A tmux plugin that **nudges you when a pane needs a human** — by blinking or
highlighting the pane/window border. Anything can nudge you: a finished shell
script, an idle build, or an AI coding agent waiting for your response.

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

## Design (planned)

Trigger tiers → shared renderer:

| Tier    | Source                                         | Precision                  | Covers                       |
| ------- | ---------------------------------------------- | -------------------------- | ---------------------------- |
| Base    | tmux idle detection (`monitor-silence` style)  | coarse ("stopped")         | shell, scripts, builds, ssh  |
| Precise | agent hooks (Claude Code `Stop`/`Notification`)| exact (done vs needs-input)| AI agents                    |
| Middle  | PTY scrape for prompt patterns (`[y/N]`, `❯`)  | medium                     | agents without hooks         |

**Differentiator:** an actual *animated, per-pane* border pulse — not just a
static colour, and scoped to the individual pane that needs you.

## Status

Feasibility proven and the **engine core** is implemented ([`bin/nudge`](bin/nudge)):
per-pane state, a pulse daemon (auto starts/stops), the layered renderer, and
auto-clear when you focus a pane. Trigger integrations (Claude Code hook, generic
shell/idle) are next.

### Try it live (isolated — won't touch your real session)

```sh
# from a PLAIN terminal (not inside tmux):
experiments/try-engine.sh
# … watch the left pane border pulse + labels; C-b d to detach, then:
tmux -L nudgedemo kill-server
```

### CLI

```sh
nudge init                      # install formats + hooks (done by nudge.tmux)
nudge on  [-t pane] [-s state]  # state: needs-input | done | error
nudge off [-t pane]
nudge status
```

### As a plugin (TPM)

```tmux
set -g @plugin 'bmohan01/tmux-nudge'
```

### Feasibility spikes

The throwaway demos that proved each layer live:
[`experiments/blink-spike.sh`](experiments/blink-spike.sh) (border pulse) and
[`experiments/label-spike.sh`](experiments/label-spike.sh) (single-pane label).

## License

MIT
