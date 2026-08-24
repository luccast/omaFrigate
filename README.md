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

Click the camera pill to open the snapshot grid. Escape closes it. After login, the form hides and Log out appears.

```sh
omarchy-shell shell summon io.github.luccast.frigate '{}'
omarchy-shell shell hide io.github.luccast.frigate
```

Stills refresh only while the panel is open.

## Configure

Default URL is `http://127.0.0.1:5000` (Frigate's unauthenticated internal port). For the authenticated UI port, set the URL to `http://HOST:8971` and enter a username/password in the panel. The password is stored only in `~/.local/state/omarchy/frigate.json` mode `0600`.

Frigate notification flags from `/api/config` are respected. Only unseen `severity=alert` review items toast.

## Remove

```sh
omarchy plugin remove io.github.luccast.frigate
```
