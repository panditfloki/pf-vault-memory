# Log

Append-only chronological record. Entry format (parseable): `## [YYYY-MM-DD] ingest|query|lint | Title`.
Never rewrite old entries — a superseded entry stays and the newer one is added below it.

## [2026-01-01] init | Vault created

Scaffolded from the pf-vault-memory template. Edit `KERNEL.md` to make it yours, then start
capturing sessions and running `/ingest`.
