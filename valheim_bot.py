#!/usr/bin/env python3
"""valheim_bot.py - Discord slash commands for /usr/local/bin/valheim.sh

Commands:
  /valheim status
  /valheim start
  /valheim stop     (script refuses if players are online or count unknown)
  /valheim restart  (script refuses if players are online or count unknown)

Access control is handled in Discord (Server Settings -> Integrations).
The bot never passes --force.
"""
import asyncio
import os

import discord
from discord import app_commands

SCRIPT = os.environ.get("VALHEIM_SCRIPT", "/usr/local/bin/valheim.sh")
TOKEN = os.environ["DISCORD_BOT_TOKEN"]
# Optional: your server ID makes slash commands appear instantly instead of
# taking up to an hour to propagate globally.
GUILD_ID = os.environ.get("DISCORD_GUILD_ID")

EXIT_MESSAGES = {
    0: "",
    1: "Server is stopped.",
    5: "Server is already running.",
}

VERBS = {"restart": "restarting", "stop": "stopping"}


def refusal(code: int, action: str) -> str | None:
    verb = VERBS.get(action, action)
    if code == 3:
        return f"Not {verb} - players are online."
    if code == 4:
        return f"Not {verb} - can't read the player count (server may still be booting)."
    return EXIT_MESSAGES.get(code)


# Only one script call at a time so two people can't double-restart.
lock = asyncio.Lock()


async def run_script(*args: str) -> tuple[int, str]:
    proc = await asyncio.create_subprocess_exec(
        SCRIPT, *args,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.STDOUT,
    )
    try:
        out, _ = await asyncio.wait_for(proc.communicate(), timeout=150)
    except asyncio.TimeoutError:
        proc.kill()
        return 124, "script timed out"
    return proc.returncode, out.decode().strip()


intents = discord.Intents.default()  # no privileged intents needed
client = discord.Client(intents=intents)
tree = app_commands.CommandTree(client)
valheim = app_commands.Group(name="valheim", description="Valheim server controls")


async def run_action(interaction: discord.Interaction, action: str):
    await interaction.response.defer(thinking=True)
    if lock.locked():
        await interaction.followup.send("Another command is already running, try again in a moment.")
        return
    async with lock:
        code, out = await run_script(action)
    note = refusal(code, action) or f"Script failed (exit {code})."
    msg = out if code == 0 else (note or out)
    await interaction.followup.send(f"```\n{msg}\n```")


@valheim.command(name="status", description="Show server status and player count")
async def status(interaction: discord.Interaction):
    await interaction.response.defer(thinking=True)
    async with lock:
        code, out = await run_script("status")
    await interaction.followup.send(f"```\n{out or EXIT_MESSAGES.get(code, 'no output')}\n```")


@valheim.command(name="start", description="Start the server")
async def start(interaction: discord.Interaction):
    await run_action(interaction, "start")


@valheim.command(name="stop", description="Stop the server (only if nobody is on)")
async def stop(interaction: discord.Interaction):
    await run_action(interaction, "stop")


@valheim.command(name="restart", description="Restart the server (only if nobody is on)")
async def restart(interaction: discord.Interaction):
    await run_action(interaction, "restart")


tree.add_command(valheim)


@client.event
async def on_ready():
    if GUILD_ID:
        guild = discord.Object(id=int(GUILD_ID))
        tree.copy_global_to(guild=guild)
        await tree.sync(guild=guild)
    else:
        await tree.sync()
    print(f"logged in as {client.user}", flush=True)


client.run(TOKEN)
