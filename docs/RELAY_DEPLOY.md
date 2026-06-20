# Skirmish Relay — deploy & operate

This is how online Skirmish works **without players installing Tailscale or
forwarding ports**. Both players connect *outward* to a small relay you run; the
relay pairs them by a 4-character room code and forwards packets between them.
Outbound connections punch through any home router (including CGNAT), so the only
machine that needs a reachable address is the relay.

```
  Player A  ──out──▶  ┌───────────┐  ◀──out──  Player B
  (Varna)             │   RELAY   │            (Balchik)
  "HOST ONLINE"       │  room: AB23│            "JOIN ONLINE: AB23"
  gets code AB23      └───────────┘            paired → fight
```

The relay is the **same Godot project** run headless with one script
([`tools/relay_server.gd`](../tools/relay_server.gd)) that drives the `NetMatch`
autoload into relay mode (`run_as_relay`). No separate codebase, so the RPC
message shapes can never drift from the game.

---

## 1. Play *right now* (local / same network — no VPS)

You don't need a server to test the room-code flow:

- **One PC, two windows:** run the game twice. In window 1: *Skirmish → Online →*
  expand **“Same network / direct IP”** → **HOST (LAN)**. In window 2: type
  `127.0.0.1` → **JOIN**. (The direct path is unchanged and fully verified.)
- **Two PCs, same WiFi:** host on one, the other joins the host's `192.168.x.x`.

To exercise the **room-code relay path** locally, start a relay on your machine
and point the game at `127.0.0.1` (see §4 “testing” override):

```sh
# terminal 1 — the relay
Godot_console.exe --headless --path "D:\Godot" --script res://tools/relay_server.gd

# then in two game windows: HOST ONLINE → get code → JOIN ONLINE with that code
```

---

## 2. Stand up the public relay (a tiny VPS)

A turn-based card game needs almost nothing. A €4/mo Hetzner box in Falkenstein
or Nuremberg is ~30–50 ms from Bulgaria and is plenty. Any Linux VPS works.

**a. Install headless Godot on the VPS** (matching the project's 4.6.x):

```sh
cd /opt
wget https://github.com/godotengine/godot/releases/download/4.6.2-stable/Godot_v4.6.2-stable_linux.x86_64.zip
unzip Godot_v4.6.2-stable_linux.x86_64.zip
mv Godot_v4.6.2-stable_linux.x86_64 /usr/local/bin/godot
chmod +x /usr/local/bin/godot
```

**b. Copy the project to the VPS.** The relay loads the `NetMatch` autoload, so it
needs the project (it's small — no build step). From your machine:

```sh
rsync -az --delete \
  --exclude '.git' --exclude 'assets' --exclude 'tools/screenshot' \
  "D:/Godot/" you@your-vps:/opt/burning-meadow/
```

(You can prune further later; `project.godot` + `scripts/` is the real
requirement. Keeping the whole repo is simplest and harmless.)

**c. Open the port.** The relay listens on **UDP 7717** (`RELAY_PORT_DEFAULT`):

```sh
ufw allow 7717/udp
```

**d. Run it under systemd** so it restarts on crash/reboot.
`/etc/systemd/system/bm-relay.service`:

```ini
[Unit]
Description=Burning Meadow Skirmish relay
After=network.target

[Service]
ExecStart=/usr/local/bin/godot --headless --path /opt/burning-meadow --script res://tools/relay_server.gd
Restart=always
RestartSec=3
User=bmrelay
# Optional: override the port
# Environment=RELAY_PORT=7717

[Install]
WantedBy=multi-user.target
```

```sh
useradd -r -s /usr/sbin/nologin bmrelay
systemctl daemon-reload
systemctl enable --now bm-relay
journalctl -u bm-relay -f      # watch the heartbeat: "alive — N room(s), M peer(s)"
```

The relay prints a heartbeat every 30 s with the live room/peer count — that's
your health check.

---

## 3. (Other half of “do both”) Steam relay — later

When a Steam build happens, Valve's relay (via GodotSteam's `SteamMultiplayerPeer`)
gives the same NAT-free play with **zero servers and zero cost**, and players
connect by Steam friend/lobby instead of a typed code. That swaps only the
transport peer — the room/envelope layer here is already transport-agnostic, so
it drops in as a third `Transport` mode without touching Draft/Combat. Tracked as
Phase 5 in [`MULTIPLAYER_SKIRMISH_PLAN.md`](MULTIPLAYER_SKIRMISH_PLAN.md). Run the
self-hosted relay now; add Steam alongside it for the Steam release.

---

## 4. Point the game at your relay

The lobby resolves the relay address in this order
([`NetMatch.get_relay_host()`](../scripts/net/NetMatch.gd)):

1. **`BM_RELAY_HOST` env var** — handy for testing (`BM_RELAY_HOST=127.0.0.1`).
2. **`user://relay_host.txt`** — a one-line file with the address; lets you or a
   tester repoint without a rebuild. (`user://` is the Godot user data dir.)
3. **`NetMatch.RELAY_HOST_DEFAULT`** — the baked-in shipping address.

**For release builds, set the constant** in
[`scripts/net/NetMatch.gd`](../scripts/net/NetMatch.gd):

```gdscript
const RELAY_HOST_DEFAULT: String = "relay.yourdomain.net"   # or the VPS IP
```

Use a DNS name, not a bare IP, so you can move the VPS later without re-shipping.
While `RELAY_HOST_DEFAULT` is empty (as in the repo), the lobby greys out the
**HOST/JOIN ONLINE** buttons and points players at the direct-IP fallback — so an
un-deployed build degrades cleanly instead of erroring.

---

## 5. Verify

Headless, three real processes (relay + host + client) over loopback, proving
create → code → join → pair → ready → seed → bidirectional forwarding:

```sh
# terminal 1
$env:SKIRM_ROLE='relay';  Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_relay.gd
# terminal 2
$env:SKIRM_ROLE='host';   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_relay.gd
# terminal 3
$env:SKIRM_ROLE='client'; Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_relay.gd
```

The default (no `SKIRM_ROLE`) runs a fast single-process logic check of code
generation and the envelope dispatch table.

---

## Security / hardening notes

- The relay only ever forwards a player's envelope to its **one** room partner
  (`server_relay` is off — the engine never auto-broadcasts). No cross-room leak.
- It's an open relay (anyone with the address can open a room). For a 1.0 launch
  that's fine; if abused, add a max-rooms cap or a shared secret in
  `_rpc_create_room` / `_rpc_join_room`.
- Packets are not encrypted in transit. For a card game that's acceptable; if you
  ever carry sensitive data, run ENet's DTLS or terminate behind WireGuard.
