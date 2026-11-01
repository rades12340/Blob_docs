# Blob_docs

Documentation for the whole Blob storage system: how the services fit together, why they were built this way, and what to do when something breaks. Published at **https://rades12340.github.io/blob_docs/**.

| Repo | What it is |
| --- | --- |
| [auth_service](https://github.com/rades12340/auth_service) | Sign-up, login, JWT access tokens, refresh cookies |
| [Blob_storage](https://github.com/rades12340/Blob_storage) | Upload, list and download files in S3 |
| [Blob_api_gateway](https://github.com/rades12340/Blob_api_gateway) | Single entry point: routing, rate limits, request ids |
| [Blob_frontend](https://github.com/rades12340/Blob_frontend) | Next.js web app |
| [Blob_observability](https://github.com/rades12340/Blob_observability) | Loki + Grafana log stack for local development |

## What goes where

- **A repo's README** covers how to run, test and change that repo.
- **This site** covers everything that spans repos: architecture, decisions (ADRs), runbooks, the API reference, operations and contributing rules. It links to the READMEs instead of copying them.

When a change in a service repo affects an endpoint, env var, port, flow or decision, open a matching PR here.

## Preview locally

```bash
python3 -m venv .venv && . .venv/bin/activate
pip install -r requirements.txt
./scripts/fetch-openapi.sh     # copies openapi.yaml from auth_service and Blob_storage main
mkdocs serve                   # http://127.0.0.1:8000, reloads on save
```

## Writing pages

- Pages live in `docs/`. The navigation is set in `mkdocs.yml`, so add new pages there too.
- Diagrams are Mermaid code blocks (`` ```mermaid ``), so they're text and reviewable in PRs.
- Callouts use admonitions: `!!! note`, `!!! warning`, `!!! tip`.
- **ADRs** (`docs/decisions/NNNN-title.md`) have the sections Status, Context, Decision and Consequences. Don't rewrite an accepted ADR: add a new one that supersedes it.
- **Runbooks** (`docs/runbooks/`) have the sections Symptoms, Check, Fix and Prevent, with copy-pasteable commands.
- The API reference is generated: `docs/api/specs/` is fetched, not committed. To change an endpoint, change `openapi.yaml` in the service repo.

## Checks

| Command | What it does |
| --- | --- |
| `mkdocs build --strict` | Builds the site. Broken links, missing pages and nav errors fail it. |
| `npx markdownlint-cli2 "docs/**/*.md"` | Markdown style. Config in `.markdownlint.yaml`. |

CI runs both on every push. `pages.yml` publishes the site on every push to `main` and weekly, so the API reference picks up specs merged in the service repos.

## PR rules

Same as the service repos: branches are named `<feat|fix|docs|chore>/<issue number>-short-slug`, and a PR needs a type label (`feature`, `enhancement`, `bug`, `documentation`) and a reference to an open issue. With Claude Code, "ship this" uses the `ship-pr` skill in `.claude/skills/`.
