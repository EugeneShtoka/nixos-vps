# Hetzner VPS — NixOS Config

**Host:** `vps` (SSH alias) — IP `65.21.3.202`, port `47293`, user `eugene`  
**Domain:** `cloud-surf.com` (DNS on Cloudflare)  
**Elevate:** `sudo su -` after SSH  
**Apply config:** `nixos-rebuild switch` on VPS (config lives at `/etc/nixos/`; this repo is a laptop mirror)

---

## Module layout

`configuration.nix` is imports-only. All config is in per-service modules:

| File | Contents |
|---|---|
| `boot.nix` | Bootloader, kernel, filesystems |
| `network.nix` | Static networking, hostname |
| `nix.nix` | Nix settings, GC, flake inputs |
| `users.nix` | System users (`eugene`, `matrix`, `orchestrator`, etc.) |
| `ssh.nix` | OpenSSH — port 47293, key-only |
| `secrets.nix` | sops-nix — all secret declarations |
| `hardening.nix` | Firewall, sysctl, kernel module blacklist, auditd |
| `vpn.nix` | Tailscale + Headscale |
| `dns.nix` | Unbound + Pi-hole (podman) |
| `password-manager.nix` | Vaultwarden |
| `vcs.nix` | Forgejo |
| `search.nix` | SearXNG |
| `sync.nix` | Syncthing |
| `monitoring.nix` | Netdata |
| `http-proxy.nix` | Tinyproxy (SSH-tunnel only) |
| `notifications.nix` | ntfy-sh |
| `proxy.nix` | nginx + ACME (Let's Encrypt DNS-01 via Cloudflare) |
| `backup.nix` | Daily backup timers → Syncthing → laptop |
| `messaging.nix` | tuwunel homeserver + 8 mautrix bridges |
| `orchestrator.nix` | vortexd workflow daemon + clipkit |

---

## Services

| Service | URL | Notes |
|---|---|---|
| Headscale | `headscale.cloud-surf.com` (public) | VPN control plane |
| Pi-hole | `100.64.0.1:53` | VPN DNS; admin :8083 |
| Vaultwarden | `vault.cloud-surf.com` | VPN-only |
| Forgejo | `git.cloud-surf.com` | VPN-only; SSH git on :2222 |
| SearXNG | `seer.cloud-surf.com` | VPN-only |
| Netdata | `netdata.cloud-surf.com` | VPN-only |
| Syncthing | `syncthing.cloud-surf.com` | VPN-only |
| tinyproxy | `localhost:8888` (SSH tunnel) | HTTP proxy for bridge re-logins |
| ntfy-sh | `ntfy.cloud-surf.com` | Push notifications |
| tuwunel | `matrix.cloud-surf.com` | Matrix homeserver (VPN-only) |

---

## Matrix stack

```
bridges (8) → mx-proxy (:8901 AS, :8900 CS) → tuwunel (:6167)
                        ↓ Unix socket
                    vortexd → ntfy / clipkit
```

- **mx-proxy** runs as user `matrix`; must be in group `orchestrator` to reach `/run/vortex/vortex.sock`
- **vortexd** runs as user `orchestrator`; socket mode `0770` (owner `orchestrator:orchestrator`)
- **Pitfall:** if mx-proxy is started before the `orchestrator` group is applied, it will get `permission denied` on the socket — fix with `systemctl restart mx-proxy`

### Bridges

| Bridge | Port | Account |
|---|---|---|
| whatsapp-bg | 29318 | +359884650326 |
| whatsapp-il | 29319 | +972545347450 |
| slack | 29320 | — |
| meta | 29321 | Facebook + Instagram |
| linkedin | 29322 | — |
| telegram | 29323 | — |
| signal | 29328 | — |
| gmessages | 29336 | — |

### vortexd workflow (mx-message)

Triggered by mx-proxy for every intercepted message:

1. `notify` — POST plain text to `ntfy/mx-notify` (only when `event_id == ""`)
2. `fetch_state` — GET room state from tuwunel (when `event_id != ""`)
3. `matched_space` — CEL eval: find first matching space from `MATRIX_SPACES`
4. `notify_space` — POST matrix.to link to `ntfy/mx-notify-{space}` (when matched)
5. `extract_url` / `extract_code` — clipkit (when no space matched)
6. `notify_clipboard` — POST extracted content to `ntfy/mx-clipboard`

---

## Secrets

Managed by sops-nix. Encrypted with age key at `~/.config/sops/age/keys.txt` (laptop).  
Edit: `SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt nix run nixpkgs#sops -- edit secrets.yaml`

---

## Headscale nodes

| Node | IP | Notes |
|---|---|---|
| vps | 100.64.0.1 | VPS itself |
| laptop | 100.64.0.2 | — |
| phone-s21 | 100.64.0.3 | — |

Add device: `headscale preauthkeys create -u 1 --reusable --expiration 2h`  
⚠️ v0.27 quirk: `preauthkeys create` requires numeric user ID (not name string)

---

## Backups

Daily at 03:00 UTC → `/var/lib/server-backup/` → Syncthing → `~/Backups/` on laptop.  
Restore instructions: `~/Backups/RESTORE.md`
