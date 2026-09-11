# omaFrigate

Check your Frigate cameras from the Omarchy bar.

View latest stills, a floating live view, and review Frigate alerts without opening a browser. Click a toast or the bar icon to see what happened or enable live popup alerts to show a live stream of a detection as it happens.

![omaFrigate panel with camera stills and review alerts](preview.jpg)

Plugins run unsandboxed inside `omarchy-shell` with your user permissions. Read the code before you enable it.

## Requirements

- [Omarchy](https://omarchy.org/) with shell plugin support
- A reachable [Frigate](https://frigate.video/) instance (0.14+ for review alerts)
- [`mpv`](https://mpv.io/) on `PATH` for live windows and clips

## Install

```sh
omarchy plugin add https://github.com/luccast/omaFrigate.git --enable
```

The widget lands on the right side of the bar. Move it with:

```sh
omarchy bar move io.github.luccast.frigate
```

Update later with `omarchy plugin update io.github.luccast.frigate`.

## Connect

Click the bar icon. The first time, you get a connection form.

| Frigate | URL | Username / password |
| --- | --- | --- |
| Same machine, unauthenticated API | `http://127.0.0.1:5000` | Leave blank |
| Authenticated UI | `http://HOST:8971` | Frigate user |

The password is stored only in `~/.local/state/omarchy/frigate.json` (`0600`). After a successful login, the form hides. Use the header logout button to sign out and clear credentials.

The header browser icon opens Frigate in your default browser.

## Use

| Action | Result |
| --- | --- |
| Click the bar icon | Open or close the panel |
| Escape | Close the panel |
| Click a camera still | Open a floating `mpv` live view and close the panel |
| Click an alert | Play the clip (or go live if it is still in progress) and mark it reviewed |
| Check on an alert | Dismiss it |
| Mark all | Mark every listed alert reviewed |

The status line shows Frigate version, recordings disk free, and detector time. Each camera tile shows fps or offline, plus the last review object.

Stills refresh only while the panel is open.

## Live windows

Each camera opens its own `mpv` window, tagged with a Wayland app-id of
`omaFrigate-live-slot0` through `omaFrigate-live-slot3` (cycling after 4
concurrently open views) so up to 4 can line up in a 2x2 grid, filling most
of the screen, instead of stacking on each other — Hyprland ignores mpv's own
`--geometry` positioning hint for new floating windows, so the position has
to come from a per-slot window rule instead. Closing one view immediately
frees its slot for the next one (the first free slot is reused, not the next
number in sequence). Super-drag moves a window; the window close button or
`q` closes one.

By default the stream is Frigate's MJPEG endpoint (`/api/<camera>`). In the panel gear, **Higher quality stream** switches to the camera's RTSP main stream (H264). That needs the camera's own username and password, not the Frigate login.

Add this to `~/.config/hypr/hyprland.lua` (after Omarchy's defaults) so the windows float instead of tiling. Each slot gets a static position rule forming a 2x2 grid. The coordinates below assume a 1920x1080 panel at 1.6x scale (logical resolution 1200x675); Hyprland's `monitor_w`/`window_w` move expressions evaluate against a different coordinate space on a scaled monitor, so the positions are plain logical pixels:

```lua
local omafrigate_live_base = {
  tag = "-default-opacity",
  float = true,
  pin = true,
  no_dim = true,
  opacity = "1 1",
  keep_aspect_ratio = true,
}

local omafrigate_live_size = { 528, 297 }

-- 2x2 grid centered on the 1200x675 logical board: 528-wide windows, 16px
-- gaps, 64px side and ~32px top/bottom margins.
local omafrigate_slot = {
  { 64, 32 },    -- slot0 top-left
  { 608, 32 },   -- slot1 top-right
  { 64, 345 },   -- slot2 bottom-left
  { 608, 345 },  -- slot3 bottom-right
}

for slot, pos in ipairs(omafrigate_slot) do
  local appid = "^omaFrigate-live-slot" .. (slot - 1) .. "$"
  local rule = {}
  for key, value in pairs(omafrigate_live_base) do
    rule[key] = value
  end
  rule.size = omafrigate_live_size
  o.window(appid, rule)
  o.window(appid, { float = true, move = { pos[1], pos[2] } })
end
```

Size and `move` are split into two `o.window()` calls because combining them
in one rule makes placement non-deterministic on Hyprland 0.54+
(hyprwm/Hyprland#13409). For other monitor sizes, adjust the positions to
`(monitor_w - (cols * window_w + (cols - 1) * gap)) / 2 +
 col * (window_w + gap)` for each `col` (and likewise for rows), using the
logical resolution of your monitor.

Hyprland reloads on save. If a window looks wrong, run `hyprctl reload` and check `hyprctl configerrors`.

## Alerts

omaFrigate polls Frigate reviews and only toasts **unseen `severity=alert` items**. A camera that is temporarily muted in Frigate stays silent. Frigate's email/webpush notification service can stay off.

Click a toast to open the panel. Turn on **Live popup on alerts** in settings if you also want the floating camera to appear; that is off by default.

The **Alerts** list shows unreviewed alerts with thumbnails.

## Settings

Open the gear in the panel header (visible after login).

| Setting | Default |
| --- | --- |
| Live popup on alerts | Off |
| 4:3 aspect ratio | Off (16:9) |
| Still refresh (seconds) | 2 |
| Higher quality stream | Off (MJPEG) |

## Remove

```sh
omarchy plugin remove io.github.luccast.frigate
```

## Develop

From this checkout:

```sh
PLUGIN_ID=io.github.luccast.frigate
PLUGIN_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
mkdir -p "$(dirname "$PLUGIN_DIR")"
rsync -a --delete --exclude .git ./ "$PLUGIN_DIR/"
omarchy plugin validate "$PLUGIN_DIR"
omarchy plugin enable "$PLUGIN_ID"
```

Omarchy rejects plugin-folder symlinks, so copy rather than link. Saving files under `~/.config/omarchy/plugins/` reloads the plugin.

```sh
omarchy-shell shell summon io.github.luccast.frigate '{}'
omarchy-shell shell hide io.github.luccast.frigate
```

## License

[MIT](LICENSE)
