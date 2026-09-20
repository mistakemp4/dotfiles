# Keybinds

`Mod` = Super/Windows key. Press `Mod+Shift+/` any time for niri's live overlay of these.

## Launch

| Key | Action |
|---|---|
| `Mod+T` | Terminal (alacritty) |
| `Mod+D` | App launcher |
| `Mod+B` | Brave |
| `Mod+S` | Spotify |
| `Mod+E` | File manager (thunar) |
| `Ctrl+Shift+Escape` | System monitor (btop, in terminal) |

## Windows

| Key | Action |
|---|---|
| `Mod+Q` | Close window |
| `Mod+F` | Maximize column |
| `Mod+Shift+F` | Fullscreen |
| `Mod+Ctrl+F` | Expand column to available width |
| `Mod+V` | Switch focus: floating / tiling |
| `Mod+Shift+V` | Toggle window floating |
| `Mod+W` | Toggle column tabbed display |
| `Mod+R` | Cycle preset column widths |
| `Mod+Shift+R` | Cycle preset window heights |
| `Mod+Ctrl+R` | Reset window height |
| `Mod+Minus` / `Mod+Equal` | Column width -10% / +10% |
| `Mod+0` | Column width to 50% |
| `Mod+Shift+Minus` / `Mod+Shift+Equal` | Window height -10% / +10% |
| `Mod+Shift+0` | Window height to 100% |
| `Mod+BracketLeft` / `Mod+BracketRight` | Expel/consume window left/right |
| `Mod+Comma` | Consume window into column |
| `Mod+Period` | Expel window from column |

## Focus & move

| Key | Action |
|---|---|
| `Mod+H/J/K/L` or arrows | Focus left/down/up/right |
| `Mod+Ctrl+H/J/K/L` or arrows | Move column/window left/down/up/right |
| `Mod+Home` / `Mod+End` | Focus first/last column |
| `Mod+Ctrl+Home` / `Mod+Ctrl+End` | Move column to first/last |
| `Mod+Shift+arrows` | Focus monitor left/right/up/down |
| `Mod+Shift+Ctrl+arrows` | Move column to monitor |
| `Mod+Wheel` | Focus window/workspace up/down |
| `Mod+Shift+Wheel` | Focus column/monitor left/right |
| `Mod+Ctrl+Wheel` | Move column to workspace up/down |

## Workspaces

| Key | Action |
|---|---|
| `Mod+1..9` | Focus workspace 1-9 |
| `Mod+Shift+1..9` | Move column to workspace 1-9 (follow) |
| `Mod+Ctrl+1..9` | Move column to workspace 1-9 (stay put) |
| `Mod+O` | Toggle overview |

## Noctalia shell

| Key | Action |
|---|---|
| `Mod+Space` | Control center |
| `Mod+N` | Notification center |
| `Mod+Shift+N` | Clear notification history |
| `Mod+Alt+N` | Toggle Do Not Disturb |
| `Mod+C` | Clipboard history |
| `Mod+Alt+C` | Clear clipboard history |
| `Ctrl+Alt+E` | Power menu |
| `Ctrl+Alt+S` | Noctalia settings |
| `Ctrl+Alt+Q` | Lock screen |
| `Ctrl+Alt+C` | Enlarge cursor |

## Power menu (after `Ctrl+Alt+E`)

| Key | Action |
|---|---|
| `L` | Lock |
| `Ctrl+L` | Lock and suspend |
| `E` | Log out |
| `R` | Reboot |
| `P` | Shut down |

## Screenshots & misc

| Key | Action |
|---|---|
| `Ctrl+Shift+Page_Up` | Screenshot: selection |
| `Ctrl+Shift+Page_Down` | Screenshot: full screen |
| `Mod+Shift+P` | Power off monitors |
| `Mod+Escape` | Toggle keyboard shortcut inhibit |
| `Ctrl+Alt+Delete` | Quit niri |

## mpv — Anime4K

Pick by **source resolution**, not by taste. A shader chain has to upscale 4x
total, so a 1080p source needs less work than a 480p one.

| Key | Action |
|---|---|
| `Ctrl+1` | Mode A (HQ) — 1080p source ← the usual one |
| `Ctrl+2` | Mode B (HQ) — 720p source |
| `Ctrl+3` | Mode C (HQ) — 480p / noisy / old rip |
| `Ctrl+4` | Mode A+A — doubled restore pass, heavier |
| `Ctrl+5` | Mode B+B |
| `Ctrl+6` | Mode C+A |
| `Ctrl+7` | Mode A + line darken/thin — restyle, not accuracy |
| `Alt+1/2/3` | Light A/B/C (M networks) — 4K source, or a game is running |
| `Ctrl+0` | Shaders off |

| Key | Action |
|---|---|
| `d` | Toggle deband (fixes gradient banding) |
| `i` / `I` | Stats overlay / page 4 (frame timings) |
| `Alt+S` | Toggle interpolation |

## Window animation shaders

Not keybinds — a terminal command. `niri-shader` swaps the GLSL that runs
when a window opens, closes or resizes. niri hot-reloads it instantly.

| Command | Action |
|---|---|
| `niri-shader list` | All installed, `*` = active |
| `niri-shader tour` | **Preview every one in turn**, changes nothing |
| `niri-shader tour close` | Preview just the close ones |
| `niri-shader demo close glitch-out` | Preview one, then revert |
| `niri-shader close glitch-out` | Set it for real |
| `niri-shader close glitch-out 800` | Set it and override the duration (ms) |
| `niri-shader open off` | Back to niri's default |
| `niri-shader status` | What's active |

Shaders live in `~/.config/niri/shaders/*.frag` — edit them and re-run
`niri-shader <slot> <name>` to reload.
