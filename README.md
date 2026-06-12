# NS2 CBM Server

Natural Selection 2 dedicated-server config for the x76 EU server.

## Files

- `config/MapCycle.json` - maps, map-specific Workshop mods, startup Workshop mods.
- `config/ServerConfig.json` - server name, player limits, browser settings.
- `config/ConsistencyConfig.json` - client consistency rules.
- `config/shine/BaseConfig.json` - Shine enabled plugins and web config mapping.
- `config/shine/UserConfig.json` - Shine admins and groups.
- `config/shine/plugins/BaseCommands.json` - Shine base command settings.
- `config/shine/plugins/WorkshopUpdater.json` - Shine Workshop update monitor.
- `config/shine/plugins/switchteams.json` - [Shine] Switch Teams config.
- `config/shine/plugins/wonitor.json` - Wonitor Shine plugin config.
- `config/NS2Panel.json` - NS2Panel standalone mod config.
- `docs/ADDON_DOCUMENTATION_LINKS.md` - documentation/source links for addons in this stack.
- `.env.example` - host-specific launch values.
- `scripts/start-linux.sh` - runtime launcher and config validation.

## Server Profile

- Players: 20.
- Spectators: 5.
- Reserved slots: 0.
- Startup map: `ns2_biodome`.
- Balance mod: BDT Community Balance Mod, Workshop `2934445221`.
- Shine: Workshop `117887554`; built-in plugins are enabled in `config/shine/BaseConfig.json`.
- NS2Panel: Workshop `2856795526`; config is `config/NS2Panel.json`.
- Wonitor: Workshop `593421222`; config is `config/shine/plugins/wonitor.json`.
- x76 EU reference: `https://ns2servers.pw/server/136.243.135.61:27015`

`config/MapCycle.json` is the source of truth for mounted Workshop IDs. Steam downloads the current Workshop version for each listed ID.

## Host Setup

Install Linux dependencies:

```bash
sudo dpkg --add-architecture i386
printf '%s\n' 'steamcmd steam/question select I AGREE' 'steamcmd steam/license note' | sudo debconf-set-selections
sudo apt-get update
sudo apt-get install -y ca-certificates lib32gcc-s1 lib32stdc++6 python3 steamcmd
```

Create the server user and directories:

```bash
sudo groupadd --system ns2server || true
sudo useradd --system --create-home --home-dir /home/ns2server --gid ns2server --shell /usr/sbin/nologin ns2server || true
sudo install -d -o ns2server -g ns2server /home/ns2server/ns2
sudo install -d -o ns2server -g ns2server /home/ns2server/ns2/serverfiles
sudo install -d -o ns2server -g ns2server /home/ns2server/ns2/logs
sudo install -d -o ns2server -g ns2server /home/ns2server/ns2/workshop
```

Put this repo on the host, then set permissions:

```bash
sudo chown -R root:ns2server .
sudo find . -type d -exec chmod 750 {} +
sudo find . -type f -exec chmod 640 {} +
sudo chmod 750 scripts/start-linux.sh
sudo install -o ns2server -g ns2server -m 600 .env.example .env
sudo install -d -o ns2server -g ns2server -m 750 config/shine/logs
sudo chown ns2server:ns2server config/NS2Panel.json config/shine/plugins/*.json
sudo chmod 600 config/NS2Panel.json config/shine/plugins/*.json
```

Edit `.env`:

- Set `SERVER_NAME`.
- Change ports only if the host needs it.
- Keep `WEB_ADMIN=0`, or set a strong `WEB_PASSWORD` and restrict `8080/tcp` to your admin IP.

Install or update the NS2 dedicated server:

```bash
sudo -u ns2server steamcmd +force_install_dir /home/ns2server/ns2/serverfiles +login anonymous +app_update 4940 validate +quit
sudo -u ns2server /home/ns2server/ns2/serverfiles/steam-runtime/setup.sh
```

Open firewall ports:

```bash
sudo ufw allow 27015/udp
sudo ufw allow 27016/udp
sudo ufw allow 27017/tcp
```

Only if `WEB_ADMIN=1`:

```bash
sudo ufw allow from YOUR_ADMIN_IP to any port 8080 proto tcp
```

## Required Config

Add admins in `config/shine/UserConfig.json`:

```json
"Users": {
  "123456789": {
    "Group": "owner"
  }
}
```

Set `config/NS2Panel.json`:

- Create a token at `https://ns2panel.com/`.
- Put it in `AuthToken`.
- Keep the file private.

Set `config/shine/plugins/wonitor.json` if Wonitor should report to a real web instance:

- `WonitorURL`: `http://YOUR_HOST/wonitor/update.php`
- `MenuEntryUrl`: `http://YOUR_HOST/wonitor/`
- `ServerIdentifier`: same value allowed by the Wonitor web config.

The bundled default Wonitor URL is `http://localhost/wonitor/update.php`. The Wonitor Shine plugin uses HTTP.

## Start

Print and validate the launch command:

```bash
sudo -u ns2server ./scripts/start-linux.sh --print-command
```

Start the server:

```bash
sudo -u ns2server ./scripts/start-linux.sh
```

`--print-command` allows an empty NS2Panel token so you can inspect the command. Real startup fails until `config/NS2Panel.json` has `AuthToken` set.

## Verification

The printed command must contain:

- `-limit 20`
- `-speclimit 5`
- `-mods2`
- `2934445221`

The printed command must not contain `-webpassword` unless `WEB_ADMIN=1`; printed passwords are redacted.

After first start, check the server logs:

```bash
! grep -iE 'failed|missing mod|error loading wonitor|HiveVision' /home/ns2server/ns2/logs/*.log
```

No matches should appear.

Check the public listing:

```text
https://ns2servers.pw/server/YOUR_IP:27015
```

It should show the x76 EU stack plus CBM, including:

- `2934445221` BDT Community Balance Mod
- `3558697165` UWE Hotfix 344
- `117887554` Shine Administration
- `593421222` Wonitor
- `2856795526` NS2Panel

From the server or client console, run:

```text
sh_listplugins
```

Expected Shine plugin entries include:

- `switchteams`
- `wonitor`
- `workshopupdater`
- `votealltalk`
- `votedraw`
- `voterandom`
- `votesurrender`

Join the server from an NS2 client. There should be no missing-mod error, no repeated `HiveVision_camera` error, and no stuck main-menu overlay during gameplay.
