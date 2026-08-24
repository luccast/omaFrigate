# omaFrigate

Local Frigate cameras in the Omarchy bar. The panel shows latest stills. Desktop notifications fire for Frigate review alerts and honor Frigate's own notification settings.

Plugins run unsandboxed inside `omarchy-shell` with your user permissions.

## Install

```sh
omarchy plugin add https://github.com/luccast/omaFrigate.git --enable
```

While developing from this checkout:

```sh
PLUGIN_ID=io.github.luccast.frigate
PLUGIN_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
mkdir -p "$(dirname "$PLUGIN_DIR")"
rsync -a --delete --exclude .git ./ "$PLUGIN_DIR/"
omarchy plugin validate "$PLUGIN_DIR"
omarchy plugin enable "$PLUGIN_ID"
```

Omarchy rejects plugin-folder symlinks, so copy rather than link.

## Usage

Click the camera pill to open the snapshot grid. Escape closes it. After login, the form hides. Header icons open Frigate in a browser or log out. Click a still to open a floating mpv live view. Super-drag moves it; the window X or `q` closes it. The status line shows Frigate version, recordings disk free, and detector time. Each camera shows fps or offline plus the last review object.

```sh
omarchy-shell shell summon io.github.luccast.frigate '{}'
omarchy-shell shell hide io.github.luccast.frigate
```

Stills refresh only while the panel is open.

## Configure

Default URL is `http://127.0.0.1:5000` (Frigate's unauthenticated internal port). For the authenticated UI port, set the URL to `http://HOST:8971` and enter a username/password in the panel. The password is stored only in `~/.local/state/omarchy/frigate.json` mode `0600`.

Live view launches mpv against `/api/<camera>` (MJPEG). Add this after Omarchy's Hyprland defaults so the window floats and stays out of tiling:

```lua
o.window("^omaFrigate-live$", {
  tag = "-default-opacity",
  float = true,
  pin = true,
  no_dim = true,
  opacity = "1 1",
  size = { 640, 360 },
  keep_aspect_ratio = true,
  move = { "(monitor_w-window_w-40)", "(monitor_h-window_h-40)" },
})
```

Frigate notification flags from `/api/config` are respected. Only unseen `severity=alert` review items toast.

## Remove

```sh
omarchy plugin remove io.github.luccast.frigate
```
