# HerdrAppBar

A macOS menu bar companion for [herdr](https://herdr.dev) that shows the agents of
**both** herdr apps in one place: the **herdr-app** desktop app and the **herdr
TUI** that runs inside a terminal.

It is a fork of HerdrBar: bigbug16 wrote it as
[herdr-topbar](https://github.com/bigbug16/herdr-topbar), and Marcel Panse
continued it as [herdr-osx-menubar](https://github.com/marcelpanse/herdr-osx-menubar),
a herdr TUI plugin. This fork keeps its panel, icon and blink, and changes where
the state comes from. See [NOTICE](NOTICE).

## What it does

**Left click** opens the **agents panel**: every herdr-app space and every TUI
workspace, and every agent in them with what it is working on and how it is doing.

```
┌────────────────────────────────────────────┐
│  Herdr (2 spaces, 5 agents)                │
│  ────────────────────────────────────────  │
│   ●  ideas Herdr       1 working  4 agents │
│      ~/src/ideas                           │
│      ●  Herdr sidebars             working │
│      ●  027 PR #3 cleanu             ready │
│      ●  Jira ticket IDE-9071         ready │
│      ●  Ideas main                   ready │
│   ●  ~ Herdr TUI           1 ready  1 agent│
│      ~                                     │
│      ●  Claude Code                  ready │
└────────────────────────────────────────────┘
```

- **Sources.** herdr-app spaces come first, then TUI workspaces. Each header is
  tagged `Herdr` or `Herdr TUI` (the tooltip says it too). Whichever app isn't
  running is left out; "Herdr is not running" shows only when neither answers.
- **Space header**: its name, bold when that app is currently showing it, and a
  summary on the right: how many agents share the loudest status, then the total.
  Clicking it switches to that space.
- **The dim line** beneath is the folders the space's agents are working in.
- **Agent lines** carry the tab's name, or the terminal's title for a tab nobody
  named, and the agent's status. Clicking one focuses that agent and brings its
  app forward: Herdr for a herdr-app agent, the terminal hosting the TUI for a TUI
  agent.
- Spaces with no agents stay listed, dimmed, so a project you have open but
  forgotten about is still visible.
- Spaces follow each app's own order. Agents *within* a space are sorted loudest
  first, so what needs attention is never below the fold.

Statuses, in the order that matters when a space has to be summed up in one word
(waiting beats finished beats busy):

| Panel | herdr | Meaning |
|---|---|---|
| **needs you** | `blocked` | The agent is waiting on an answer |
| **done** | `done` | Finished work you have not looked at yet |
| working | `working` | Busy |
| ready | `idle` | Ready for input, nothing to report |

The panel updates while it is open, so a status that changes under you is
reflected without closing it. Escape or a click anywhere outside dismisses it.
Opening it never steals focus from the app you are in.

**Right click** opens a short menu with what the panel cannot hold:

- **Open Herdr**: only when neither Herdr's window nor a terminal attached to the
  TUI is open; it opens the herdr-app
- **Waiting for Input**: which agent is waiting, and in which project
- **Blink Duration**, **Start at Login**
- **Quit HerdrAppBar**

### The icon and its badge

**At rest the icon is an AppKit template image**, so it behaves like every other
icon in the menu bar: white on a dark bar, black on a light one, inverted while
its menu is open, and correct under Increase Contrast.

**A count badge** sits beside it whenever either app has agents that are not
merely idle: the number of agents, in the colour of the loudest one (red for
`needs you`, green for `done`, amber for `working`). When everything is idle the
badge disappears.

**An agent waiting for input** makes the icon swap to the badge's colour and back,
three times a second. It stops when the app that agent lives in comes to the
front (Herdr for a herdr-app agent, the TUI's terminal for a TUI agent), and
leaves the badge while the agent is still waiting. A *different* agent blocking
later starts the blink again.

It also stops on its own after **Blink Duration**, so an agent left waiting
overnight is not still blinking in the morning:

| Choice | Behaviour |
|---|---|
| 1 minute | Blink for a minute, then hold the badge |
| **3 minutes** | Default |
| 10 minutes | For longer unattended runs |
| Until clicked | Never stops on its own |

### About notifications

Both herdr apps deliver their own notifications. **HerdrAppBar posts none and
changes none of them.** It only makes an existing "agent is waiting" state easy
to notice from across the screen.

## Install

```bash
git clone https://github.com/bjarkebm/herdr-osx-menubar.git herdrbar-app
cd herdrbar-app

bash scripts/build.sh --install      # builds, copies to ~/Applications, restarts a running copy
open ~/Applications/HerdrAppBar.app
```

To keep it in the menu bar after a restart, right-click the icon and choose
**Start at Login**, or run `bash scripts/install-login-item.sh`. Both install the
LaunchAgent `~/Library/LaunchAgents/dev.herdr.appbar.plist`.

HerdrAppBar is not a herdr plugin and installs nothing into either herdr app. It
has its own name and bundle id (`dev.herdr.appbar`), so it can run beside the
original HerdrBar; once you use this one, quit the original.

After changing any Swift source, run `bash scripts/build.sh --install` again.

## The icon artwork

The menu bar glyph is herdr's own ram, from
[`herdr.dev/assets/ram.svg`](https://herdr.dev/assets/ram.svg). The source SVG is
kept at `Resources/ram.svg`; `scripts/make-icon.sh` crops it to the ram's head
and writes the vector PDF the app bundles. Cropping to the head keeps the curled
horn and the `>-` prompt face readable at 17pt. Regenerate after changing the
artwork or the crop:

```bash
bash scripts/make-icon.sh && bash scripts/build.sh --install
```

## Configuration

`~/Library/Application Support/dev.herdr.appbar/config.json` is written on first
launch:

```json
{
  "herdrAppBinary": "~/.local/bin/herdr-app",
  "hcBinary": "~/.local/bin/hc",
  "appBundleId": "dev.herdr.app",
  "tuiSocket": "~/.config/herdr/herdr.sock",
  "herdrBinary": "",
  "terminalBundleId": "com.apple.Terminal",
  "blinkTimeoutSeconds": 180
}
```

The file holds absolute paths; `~` is shortened here.

- `herdrAppBinary`, `hcBinary`: herdr-app's CLI and herdr-core's. A GUI app's
  PATH never includes `~/.local/bin`, so they are called by full path.
- `appBundleId`: the herdr-app to bring forward.
- `tuiSocket`: the herdr TUI's API socket.
- `herdrBinary`: the TUI binary a new terminal window runs when a TUI agent has
  no terminal attached; empty looks in `/opt/homebrew/bin`, `/usr/local/bin`,
  `~/.local/bin` and `/usr/bin`.
- `terminalBundleId`: the terminal that window opens in. Bringing an existing
  TUI terminal forward finds whichever terminal hosts it, so switching terminals
  needs no configuration.
- `blinkTimeoutSeconds` mirrors the Blink Duration menu; `0` means "until
  clicked".

The app reads the file at launch, so restart it with `bash scripts/restart-bar.sh`
after an edit. Pointing a source's path at something that doesn't exist turns
that source off.

## How it works

```
                 ┌──▶ herdr-app ls, hc ls --json  ───▶ herdr-app spaces + agents
refresh  ────────┤
                 └──▶ herdr.sock  (session.snapshot) ─▶ TUI workspaces + agents

hc events --json ──change──▶ refresh soon (herdr-app)
every 2.5 s      ──────────▶ refresh both, off the main thread

herdr-app row ──click──▶ herdr-app do agent.focus / space.select ──▶ open -b dev.herdr.app
TUI row       ──click──▶ herdr.sock (agent.focus / workspace.focus) ─▶ its terminal.activate()
herdrappbar-open <dir> ─▶ a new herdr-app space, else a new TUI workspace
```

**The two sources are read side by side and merged.** Each refresh asks both apps
in parallel; ids are prefixed by source (`app/t7`, `tui/wK:p2`), so a space or
agent can never be mistaken for one in the other app, and every click goes back
to the app it came from.

**herdr-app is read through its CLIs.** `herdr-app ls` gives spaces, tabs and each
terminal's agent status; `hc ls --json` adds each terminal's folder. `hc events`
reports changes as they happen, and a 2.5 s poll covers what it doesn't (spaces
and tabs).

**The TUI is read through its socket**, one JSON request per connection, as the
original HerdrBar did. The original was pushed status changes by a TUI plugin
hook; HerdrAppBar installs no plugin, so it polls the socket on the same 2.5 s
beat instead.

**Neither source is found through environment variables.** herdr-app terminals can
inherit stale `HERDR_*` variables from a herdr-core started inside the TUI, and a
GUI app launched from such a terminal inherits them too. So the sources are
always found by their sockets and CLIs, and the terminal HerdrAppBar opens for the
TUI is started with those variables removed, or herdr would refuse to run as
"nested".

**Fronting the TUI's terminal uses no permissions.** Driving Terminal with
AppleScript would trigger a TCC automation prompt that can later be revoked.
Instead HerdrAppBar finds the `herdr` client process, walks its parent chain to
the GUI app that owns it, and calls `NSRunningApplication.activate()`. herdr-app
is simply brought forward by its bundle id.

**The panel is an `NSPanel`, not an `NSPopover`.** A popover draws its own
material and arrow, which cannot produce a flat dark surface with its own border.
The panel is borderless and non-activating, so it takes clicks and Escape without
pulling HerdrAppBar forward.

## Troubleshooting

```bash
# What can the app see? One section per source: running or not, host app, spaces, agents
~/Applications/HerdrAppBar.app/Contents/MacOS/HerdrAppBar --diagnose

# Live state as JSON, including exactly the agents the panel would show
~/Applications/HerdrAppBar.app/Contents/MacOS/herdrappbar-open --status

# Open the agents panel, or the folder picker, without clicking the icon
~/Applications/HerdrAppBar.app/Contents/MacOS/herdrappbar-open --panel
~/Applications/HerdrAppBar.app/Contents/MacOS/herdrappbar-open --picker
```

Compare `--diagnose` with what the apps themselves report: `herdr-app ls` for
herdr-app, and `herdr workspace list` / `herdr agent list` for the TUI.

- **A source shows as not running** while it is: check its path in `config.json`.
- **"host: none" for the TUI** while it is running: the TUI server has no client
  attached. Clicking a TUI agent opens a terminal running `herdr` to attach one.

To exercise the blink with the TUI, make herdr emit a status for any pane:

```bash
herdr pane report-agent <PANE_ID> --source selftest --agent claude --state blocked
herdr pane report-agent <PANE_ID> --source selftest --agent claude --state idle
herdr pane release-agent <PANE_ID> --source selftest --agent claude
```

## Requirements

macOS 13 or later and the Swift compiler that ships with Xcode or the Command
Line Tools (for `scripts/build.sh`). For herdr-app: the Herdr desktop app with
`herdr-app` and `hc` in `~/.local/bin` (its installer puts them there). For the
TUI: herdr 0.8.0 or later. Either one is enough.

## License

MIT. See [LICENSE](LICENSE).

The licence covers the source code. It does not cover herdr's name or its ram
logo. See [NOTICE](NOTICE): `Resources/ram.svg` belongs to herdr and is included
only to identify the tool this app extends.
