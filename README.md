# Valheim Discord Control

Check on your Dockerized Valheim server and restart it from Discord, with a safety check so nobody gets kicked mid-session.

```
/valheim status    ->  valheim: running (since 2026-01-01T12:00:00Z), players: 0, join code: 123456
/valheim restart   ->  restarts the container, but only if nobody is online
```

Built for the [`lloesche/valheim-server`](https://github.com/lloesche/valheim-server-docker) image running with **crossplay** (`-crossplay`), so players on PC, Xbox, and Game Pass can all join with a join code.

## How it works

```
Discord  ->  bot (Python, discord.py)  ->  valheim.sh  ->  docker
```

- `valheim.sh` does the real work. It reads the player count and join code from the container's logs and restarts the container.
- `valheim_bot.py` registers the slash commands, runs the script, and posts the output back to Discord.
- `valheim-bot.service` keeps the bot running under systemd and starts it on boot.

You can use `valheim.sh` by itself from a terminal or cron if you don't want a bot.

## Files and where they go

| File in this repo | Install location on your server |
|---|---|
| `valheim.sh` | `/usr/local/bin/valheim.sh` |
| `valheim_bot.py` | `/opt/valheim-bot/valheim_bot.py` |
| (Python virtualenv, created in setup) | `/opt/valheim-bot/venv/` |
| `valheim-bot.service` | `/etc/systemd/system/valheim-bot.service` |
| `.env.example` (copy and fill in) | `/etc/valheim-bot.env` |

`README.md`, `LICENSE`, `.gitignore`, and `.env.example` stay in the repo and aren't installed.

## Why log parsing?

The status HTTP endpoint in the lloesche image doesn't work reliably on crossplay servers (it times out and returns no player count). The server does log a line like this on every join and leave, so the script reads that instead:

```
Player joined server "My Server" that has join code 123456, now 1 player(s)
```

**This only supports servers that write those lines.** If you run without `-crossplay`, your log wording may differ. Check with:

```bash
docker logs valheim | grep "player(s)"
```

If you see `now N player(s)` lines, it will work.

## Requirements

- A Linux host running the Valheim container (tested on Ubuntu)
- Docker, with the container started via `restart: unless-stopped` or similar
- Python 3.10+ with `venv`
- A Discord account that can manage a server

## Setup

### 1. Install the script

```bash
sudo install -m 755 valheim.sh /usr/local/bin/valheim.sh
VALHEIM_CONTAINER=valheim /usr/local/bin/valheim.sh status
```

If your container isn't named `valheim`, set `VALHEIM_CONTAINER` (see [Configuration](#configuration)). Make sure `status` works before going further.

### 2. Create the Discord app

1. Go to <https://discord.com/developers/applications> and click **New Application**.
2. **Bot** tab -> **Reset Token**. Copy the token. It's shown once, and it's a password.
3. Leave all **Privileged Gateway Intents** off. The bot doesn't need them.
4. **OAuth2 -> URL Generator**: tick the `bot` and `applications.commands` scopes. Leave the permission boxes unticked.
5. Open the generated URL in your browser and add the bot to your server.
6. In Discord, turn on **Settings -> Advanced -> Developer Mode**, then right-click your server icon and **Copy Server ID**.

### 3. Install the bot

```bash
sudo mkdir -p /opt/valheim-bot
sudo chown "$USER": /opt/valheim-bot
cp valheim_bot.py /opt/valheim-bot/
python3 -m venv /opt/valheim-bot/venv
/opt/valheim-bot/venv/bin/pip install discord.py
```

### 4. Add your secrets

```bash
sudo install -m 600 /dev/null /etc/valheim-bot.env
sudo nano /etc/valheim-bot.env
```

```
DISCORD_BOT_TOKEN=paste_token_here
DISCORD_GUILD_ID=your_server_id
```

No quotes and no spaces around `=`. `DISCORD_GUILD_ID` is optional, but without it the slash commands can take up to an hour to appear.

### 5. Run it as a service

Edit `valheim-bot.service` and change `User=` to your username (that user must be in the `docker` group, check with `id`). Then:

```bash
sudo cp valheim-bot.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now valheim-bot
journalctl -u valheim-bot -n 30 --no-pager
```

In Discord, type `/valheim`. If the commands don't show up, reload Discord with Ctrl+R.

## Controlling who can use it

Access control is handled in Discord, not in the bot. Go to **Server Settings -> Integrations -> your bot** and set permissions per command:

- Restrict `/valheim restart` to a role (for example "Valheim Admin") and leave `/valheim status` open to everyone.
- Or limit the commands to a single channel.

Anyone who is allowed to run `/valheim restart` can restart your server, but the script refuses while players are online. The bot never passes `--force`.

## Configuration

| Variable | Where | Default | What it does |
|---|---|---|---|
| `VALHEIM_CONTAINER` | environment of `valheim.sh` | `valheim` | Name of your Docker container |
| `VALHEIM_SCRIPT` | `/etc/valheim-bot.env` | `/usr/local/bin/valheim.sh` | Path to the script, if you installed it elsewhere |
| `DISCORD_BOT_TOKEN` | `/etc/valheim-bot.env` | required | Your bot token |
| `DISCORD_GUILD_ID` | `/etc/valheim-bot.env` | none | Your server ID, for instant command registration |

To pass `VALHEIM_CONTAINER` to the bot, add `VALHEIM_CONTAINER=yourname` to `/etc/valheim-bot.env`.

## Script usage and exit codes

```bash
valheim.sh status
valheim.sh restart
valheim.sh restart --force    # skips the safety checks (terminal use only)
```

| Code | Meaning |
|---|---|
| 0 | OK |
| 1 | Container is stopped |
| 2 | Usage or setup error (docker missing, container not found) |
| 3 | Restart refused: players are online |
| 4 | Restart refused: couldn't read the player count (for example, the server is still booting) |

## Is restarting safe?

With nobody online, yes. `docker restart` sends SIGTERM and waits for the container's stop timeout, and the lloesche image saves the world on shutdown. Set `stop_grace_period: 2m` in your compose file so Valheim has time to finish saving.

Two small caveats:

- If someone connects in the few seconds between the check and the restart, they'll get dropped.
- For a minute or two after a restart the server is loading, and `status` reports `players: unknown`.

The join code changes every time the container restarts, so share the new one after a restart.

## Troubleshooting

**`403 Forbidden (50001): Missing Access` in the logs.** The bot isn't in your server, or it was invited without the `applications.commands` scope, or `DISCORD_GUILD_ID` is wrong. Re-run the invite URL with both scopes and double-check the server ID.

**Commands don't appear.** Reload Discord (Ctrl+R). Without `DISCORD_GUILD_ID`, global commands can take up to an hour.

**`players: unknown` on a server that's been up a while.** The log line wasn't found. Run `docker logs valheim | grep "player(s)"` and check the wording. If the logs rotated and lost the line, restart refuses on purpose, because it can't verify the server is empty.

**Permission denied on docker.** The user in the service file isn't in the `docker` group. Fix with `sudo usermod -aG docker USERNAME`, then `sudo systemctl restart valheim-bot`.

## Security notes

- Never commit your bot token, and keep `/etc/valheim-bot.env` at mode `600`. If a token leaks, hit **Reset Token** in the Developer Portal.
- Don't post webhook URLs or tokens in chat or issues.
- Running the bot inside a Docker container means mounting `/var/run/docker.sock`, which gives that container root-equivalent control of the host. The setup above avoids this by running the bot directly on the host.

## License

MIT
