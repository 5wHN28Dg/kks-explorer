# Remote access: Cloudflare Tunnel + Cloudflare Access

Goal: technicians on mobile data, other plant networks and HQ reach the app over HTTPS, and nobody else
can reach anything. The same HTTPS address is used everywhere, including inside the plant, so the offline app,
its saved data and its queued changes are the same on every network.

```
phone / laptop ──HTTPS──► Cloudflare edge ──► Access: allowed email? ──no──► blocked (the app is never reached)
                                                  │ yes
                                                  ▼
                              tunnel (outbound from the server, port 7844)
                                                  ▼
                           cloudflared ── checks the Access token again
                                                  ▼
                           app on 127.0.0.1:8420 ── app login + roles
```

Three independent locks: Cloudflare Access (email one-time code), cloudflared's own token check, and the app's
own login. The server opens no inbound port; the tunnel is an outbound connection.

## 0. Before anything: approval and the server machine

- **Written approval from plant IT/security.** Show them this page. Points they will care about:
  - Traffic is encrypted phone→Cloudflare and Cloudflare→server, but **Cloudflare decrypts it at its edge** (that is
    how Access works). If that is not acceptable for these documents, see "If IT says no" at the end.
  - No inbound firewall rule; the server needs **outbound TCP/UDP 7844** (and 443) to Cloudflare.
  - Who gets access is a list of email addresses they can review.
- **Server machine:** always on, on the **office/IT network, never the DCS/OT (control) network**. A small Linux
  mini-PC is enough. Not your laptop: remote users need it running at night and when you are on leave.
- **A domain on Cloudflare** (free plan): buy one (~$10/year) or ask IT for a subdomain of the company's domain
  delegated to Cloudflare. Below it is `kks.example.com`.

## 1. Cloudflare Access (dashboard: Zero Trust)

1. Create the Zero Trust organisation (free up to 50 users). Pick a team name: `YOUR-TEAM.cloudflareaccess.com`.
2. **Settings → Authentication → Login methods:** add **One-time PIN** (a code sent by email). If the company uses
   Microsoft 365, IT can connect Entra ID instead, so people sign in with their work account.
3. **Access → Applications → Add → Self-hosted:** name `KKS Explorer`, domain `kks.example.com`.
   - Session duration: **1 week** (people re-enter an email code weekly; less friction than daily, still bounded).
   - Policy `Plant staff`, action **Allow**, include **Emails**: list each person (HQ included). Avoid
     "Emails ending in @gmail.com" or similar; list people individually or use the company's own domain.
   - Nothing else is allowed: Access denies whatever no policy allows.
4. Copy the application's **AUD tag** (Overview tab). You need it in step 2.

## 2. Tunnel (on the server)

```bash
# install cloudflared from Cloudflare's apt repository: https://pkg.cloudflare.com
cloudflared tunnel login                         # opens a browser: pick the domain
cloudflared tunnel create kks                    # prints TUNNEL-UUID, writes ~/.cloudflared/TUNNEL-UUID.json
cloudflared tunnel route dns kks kks.example.com
sudo mkdir -p /etc/cloudflared && sudo cp ~/.cloudflared/TUNNEL-UUID.json /etc/cloudflared/
sudo cp deploy/cloudflared-config.example.yml /etc/cloudflared/config.yml
sudoedit /etc/cloudflared/config.yml             # TUNNEL-UUID, hostname, YOUR-TEAM, AUD tag
sudo cloudflared service install && sudo systemctl enable --now cloudflared
```

## 3. The app as a service

```bash
sudo useradd --system --home /var/lib/kks-explorer --shell /usr/sbin/nologin kks
sudo mkdir -p /opt/kks-explorer /etc/kks-explorer
sudo cp -r app.py server index.html admin.html common.js sw.js manifest.webmanifest icon* \
  import_sheet.py extractor requirements-import.txt /opt/kks-explorer/
cd /opt/kks-explorer && sudo python3 app.py setup-importer && cd -   # .venv for Manage → Drawings
sudo cp deploy/config.remote.example.json /etc/kks-explorer/config.json
sudoedit /etc/kks-explorer/config.json           # public_url = https://kks.example.com, plant_name
sudo cp deploy/kks-explorer.service /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl start kks-explorer   # creates /var/lib/kks-explorer
sudo systemctl stop kks-explorer
# plant data + your existing field data (stop the laptop server first; copy plant.db together with -wal/-shm if present)
sudo cp -r data plant.db photos backups /var/lib/kks-explorer/
sudo chown -R kks:kks /var/lib/kks-explorer
sudo systemctl enable --now kks-explorer
sudo -u kks KKS_CONFIG=/etc/kks-explorer/config.json python3 /opt/kks-explorer/app.py check
```

`check` must show no `FAIL`. It verifies that the app listens on 127.0.0.1 only, that cookies are Secure, and that
the cloudflared config enforces Access tokens (run it with `sudo` if `/etc/cloudflared` isn't readable).
New manager setup links and messages go to the journal: `journalctl -u kks-explorer`.

## 4. Test before telling anyone

From a phone **on mobile data** (Wi-Fi off):

1. Open `https://kks.example.com`: the **Cloudflare** email page must appear first, before anything of the app.
2. An email that is not on the list must get "no access", with no code sent.
3. After the code: the app's own login. Sign in, open two or three sheets.
4. Add to home screen. Airplane mode: the app opens, sheets you opened show, search works, an edit is queued.
   Airplane mode off: the edit is sent (status goes back to Online).
5. From a laptop on the plant LAN: `http://SERVER-IP:8420` must **not** connect (the app listens on loopback only).
6. `curl -sI https://kks.example.com/data/tags.json` from any machine must be a redirect to
   `YOUR-TEAM.cloudflareaccess.com`, never `200`.

## Day to day

- **New person:** add their email to the Access policy **and** create their app account (Manage → Users).
- **Someone leaves:** remove the email from the Access policy **and** deactivate the app account. Either one alone
  blocks them. Doing both means one slip doesn't reopen access. Their phone keeps its offline copy until it
  reconnects (then it's wiped), or at most `offline_days` of use.
- **Weekly email code:** when the Access session expires, the status in the header shows **Sign in again**. Until
  then the app keeps working from the offline copy and queues edits. Tapping it goes through the email code and
  back. Nothing queued is lost.
- **Internet shutdowns** (e.g. exam-season cuts): the app keeps working offline for up to `offline_days`; edits
  queue until the connection returns.
- **Updating the app:** copy the new code to `/opt/kks-explorer`, `sudo systemctl restart kks-explorer`, run `check`.

## Why Cloudflare and not Tailscale

Both keep the server off the open internet and both give HTTPS. For this use:

| | Cloudflare Tunnel + Access | Tailscale |
|---|---|---|
| What users install | nothing, a web address | the Tailscale app on every phone/PC, VPN switched on |
| Cost for plant use | free up to 50 users (+ a domain) | free plan is non-commercial only; paid is per user per month |
| HQ laptops | browser only | needs a VPN client; corporate laptops often block that |
| Latency from the plant / HQ | Cloudflare has data centres near both | direct, or via relay servers abroad when mobile networks block UDP |
| Who can see the data | Cloudflare's edge decrypts the traffic | end-to-end encrypted; Tailscale can't see it |

## If IT says no to Cloudflare

Use Tailscale instead: `tailscale serve --bg --https=443 http://127.0.0.1:8420` on the server gives
`https://SERVER.TAILNET.ts.net` with a real certificate, reachable only from devices in the tailnet. Keep `host`
at `127.0.0.1`, set `public_url` to that address and `secure_cookies: true`. Restrict the tailnet policy so members
can reach only that machine on port 443. Every user then needs the Tailscale app and a paid seat.
