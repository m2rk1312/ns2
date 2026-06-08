# NS2 CBM Server

Natural Selection 2 dedicated-server profile. BAD Classic public mod stack + CommunityBalanceMod.

- `config/MapCycle.json` - map pool, map-specific Workshop mods, startup Workshop mods.
- `config/ServerConfig.json` - 20-player classic server settings.
- `config/ConsistencyConfig.json` - client consistency rules.
- `config/shine/BaseConfig.json` - Shine enabled plugins.
- `config/shine/UserConfig.json` - admins.
- `.env.example` - host values.
- `scripts/start-linux.sh` - only runtime script.

## Profile

- Players: 20.
- Spectators: 5.
- Reserved slots: 0.
- Startup map: `ns2_biodome`.
- Balance: CBM, not default NS2.
- CBM Workshop ID: `2934445221`.
- Startup mods: 21. First 20 = BAD Classic/Noob Haven public order. Last = CBM.
- UWE whitelist/ranked status not copyable. Friends can play without it.

## Setup

Linux host deps:

```bash
sudo dpkg --add-architecture i386
printf '%s\n' 'steamcmd steam/question select I AGREE' 'steamcmd steam/license note' | sudo debconf-set-selections
sudo apt-get update
sudo apt-get install -y ca-certificates lib32gcc-s1 lib32stdc++6 python3 steamcmd
```

User + dirs:

```bash
sudo groupadd --system ns2server || true
sudo useradd --system --create-home --home-dir /home/ns2server --gid ns2server --shell /usr/sbin/nologin ns2server || true
sudo install -d -o ns2server -g ns2server /home/ns2server/ns2
sudo install -d -o ns2server -g ns2server /home/ns2server/ns2/serverfiles
sudo install -d -o ns2server -g ns2server /home/ns2server/ns2/logs
sudo install -d -o ns2server -g ns2server /home/ns2server/ns2/workshop
```

Put this repo on host, then:

```bash
sudo chown -R root:ns2server .
sudo find . -type d -exec chmod 750 {} +
sudo find . -type f -exec chmod 640 {} +
sudo chmod 750 scripts/start-linux.sh
sudo install -o ns2server -g ns2server -m 600 .env.example .env
sudo install -d -o ns2server -g ns2server -m 750 config/shine/logs
```

Edit `.env`:

- `SERVER_NAME`
- ports if needed
- keep `WEB_ADMIN=0`, or set strong `WEB_PASSWORD` with at least 16 chars and restrict `8080/tcp` to your admin IP

Install/update NS2 dedicated server:

```bash
sudo -u ns2server steamcmd +force_install_dir /home/ns2server/ns2/serverfiles +login anonymous +app_update 4940 validate +quit
sudo -u ns2server /home/ns2server/ns2/serverfiles/steam-runtime/setup.sh
```

Open firewall:

```bash
sudo ufw allow 27015/udp
sudo ufw allow 27016/udp
sudo ufw allow 27017/tcp
```

Only if `WEB_ADMIN=1`:

```bash
sudo ufw allow from YOUR_ADMIN_IP to any port 8080 proto tcp
```

Check launch command:

```bash
sudo -u ns2server ./scripts/start-linux.sh --print-command
```

Start:

```bash
sudo -u ns2server ./scripts/start-linux.sh
```

## Admins

Edit `config/shine/UserConfig.json`.

Add NS2 ID:

```json
"Users": {
  "123456789": {
    "Group": "owner"
  }
}
```

Use `owner` or `moderator`.

## Required Checks

Command output must contain:

- `-limit 20`
- `-speclimit 5`
- `-mods2`
- `2934445221`

Command output must not contain `-webpassword` unless `WEB_ADMIN=1`; printed password is redacted.

Quick local check:

```bash
./scripts/start-linux.sh --print-command
```
