# Deploy and Host Bichon on Railway

Bichon is a self-hosted email archiver written in Rust. It downloads mail from your IMAP accounts (or imports EML, MBOX, Thunderbird and PST files), stores it compressed and deduplicated, builds a full-text search index, and serves a web UI and REST API to search, read and export your archive.

## About Hosting Bichon

This template runs the official Bichon 2.4.4 image (pinned by digest) as one Railway service with a volume at `/data`, built from a public GitHub wrapper repo so you get Railway's "update available" notice when we bump the version. On first boot the start script replaces Bichon's well-known default admin password with a generated one before the public port opens. Sign in as `admin` with the `BICHON_ADMIN_PASSWORD` value from the service's Variables tab. Then add IMAP accounts or import files. Bichon needs no database or search engine; everything lives on the volume. It idles at about 100 MB of RAM and runs on Railway's Free plan.

## Common Use Cases

* Keep a searchable long-term copy of Gmail, Outlook or other IMAP mailboxes
* Search across several mail accounts at once from one web UI
* Import old MBOX, EML, Thunderbird or PST archives and retire the old mail client

## Dependencies for Bichon Hosting

* A Railway volume mounted at `/data` (included)
* IMAP access to the mailboxes you want to archive (an app password for Gmail or Outlook)

### Deployment Dependencies

* Bichon on GitHub: https://github.com/rustmailer/bichon (AGPL-3.0)
* Documentation: https://bichon.rustmailer.com/docs
* Release 2.4.4: https://github.com/rustmailer/bichon/releases/tag/2.4.4
* Template repo: https://github.com/aalfath/bichon-railway-template

### Implementation Details

The template has one service, **Bichon** (web UI, REST API at `/api/v1`, OpenAPI docs at `/api-docs/swagger`, health check at `/healthz`), and sets these variables for you:

* `BICHON_ADMIN_PASSWORD`: generated admin password, set on first boot. Change it later in Settings → Profile; the variable is only used on first boot.
* `BICHON_ENCRYPT_PASSWORD`: generated key that encrypts stored IMAP passwords and OAuth tokens. Never change it after the first deploy, or saved accounts can't be decrypted.
* `BICHON_PUBLIC_URL`: your public `https://` URL, used for OAuth2 redirects. Update it if you add a custom domain.

Upstream Bichon stops itself when its storage volume has less than 1 GiB free, which would stop it on Free and Trial plan volumes (0.5 GB). This template scales that safety margin to 10% of the volume instead, and the service exits with an error (so Railway restarts it) if Bichon ever stops unexpectedly. Grow the volume in Railway when your archive gets close to full. Web uploads are capped to a quarter of the volume on small volumes; use `bichon-cli` for very large imports.

To update, apply the "update available" notice in Railway, or redeploy. Read the repo's `CHANGELOG.md` first. Left out: the optional SMTP receiver (`BICHON_ENABLE_SMTP`) needs a raw TCP port, which you can add with Railway's TCP proxy. Pro/Enterprise features need a licence from rustmailer.

## Why Deploy Bichon on Railway?

<!-- Recommended: Keep this section as shown below -->
Railway is a singular platform to deploy your infrastructure stack. Railway will host your infrastructure so you don't have to deal with configuration, while allowing you to vertically and horizontally scale it.

By deploying Bichon on Railway, you are one step closer to supporting a complete full-stack application with minimal burden. Host your servers, databases, AI agents, and more on Railway.
<!-- End recommended section -->
