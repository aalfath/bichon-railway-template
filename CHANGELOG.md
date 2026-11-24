# Changelog

## 2.4.4-1 (2026-11-24)

First release of the template.

- Bichon 2.4.4, official image pinned by digest `sha256:a282e5abf942a7b761afb48b4b3529f3be4a823f6e32d06b65a3578bd119a980`.
- Volume at `/data` (Bichon root `/data/bichon`), health check `/healthz`.
- Generated admin password replaces upstream's default on first boot; generated encryption key.
- Free-space floor scaled to the volume so Bichon runs on 0.5 GB volumes; non-zero exit on unexpected stops.
