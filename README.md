[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/new/template/bichon-2?utm_medium=integration&utm_source=button&utm_campaign=bichon)

# Bichon on Railway

One-click Railway template for [Bichon](https://github.com/rustmailer/bichon), a self-hosted email archiver: it downloads mail from IMAP accounts (or imports EML/MBOX/Thunderbird/PST files), indexes it and serves a web UI and REST API to search it.

- **App version:** Bichon 2.4.4, official image `rustmailer/bichon:2.4.4@sha256:a282e5abf942a7b761afb48b4b3529f3be4a823f6e32d06b65a3578bd119a980`
- **Services:** one, `Bichon` (web UI + REST API on `PORT`, health check `/healthz`), with a volume at `/data`. No database needed.
- **Plan:** fits Railway's Free plan (0.5 GB RAM / 1 vCPU / 0.5 GB volume). Idle memory is about 100 MB.

## After deploy

1. Open the service's public URL.
2. Sign in as `admin` with the value of `BICHON_ADMIN_PASSWORD` (service → Variables).
3. Add an IMAP account (Gmail and Outlook need an app password or OAuth2), or import mail files.

## Variables

| Variable | Default | What it does |
|---|---|---|
| `BICHON_ADMIN_PASSWORD` | generated | Password for the `admin` user, applied on first boot only. Change it later in Settings → Profile. |
| `BICHON_ENCRYPT_PASSWORD` | generated | Encrypts stored IMAP passwords and OAuth tokens. **Never change it** after the first deploy. |
| `BICHON_PUBLIC_URL` | `https://${{RAILWAY_PUBLIC_DOMAIN}}` | Public URL, used for OAuth2 redirects. Update it after adding a custom domain. |
| `PORT` | `15630` | Port Bichon listens on and Railway routes to. |

Any other upstream setting (`BICHON_LOG_LEVEL`, `BICHON_SYNC_CONCURRENCY`, `BICHON_IMAP_TIMEOUT_SECONDS`, …, see [Configuration](https://bichon.rustmailer.com/docs/configuration)) can be added as a variable.

## What this wrapper adds to the official image

- **Small volumes work.** Upstream refuses to run when its blob store has less than 1 GiB free, and stops itself with exit code 0 a few seconds after start, so it can't stay up on a 0.5 GB volume. `freefloor.c` is a tiny `LD_PRELOAD` shim that scales that floor to 10% of the volume (at least 64 MiB, at most upstream's 1 GiB) for the blob store only. Volumes of 10 GB or more behave exactly as upstream.
- **No default password.** Upstream creates `admin` / `admin@bichon`. `start.sh` changes it to `BICHON_ADMIN_PASSWORD` on a loopback-only server before the public port opens.
- **Restarts on failure.** If Bichon stops without being asked to (a crash, or the volume really filling up), the container exits non-zero so Railway's restart policy brings it back.
- **Sized to the service.** Thread counts, sync concurrency and web upload limits follow the service's CPU, memory and volume size, not the host's. Transparent huge pages are off for the process.

## Updates

Changes reach deployers through Railway's "update available" notice when this repo's `main` changes. Read [`CHANGELOG.md`](CHANGELOG.md) before applying one. Your data stays on the `/data` volume.

## Licence

Bichon is AGPL-3.0, © rustmailer.com. This wrapper only adds a start script and a shim around the unmodified official image.
