# DevSecOps Playbooks

Anonymised, reusable playbooks distilled from real production remediation sessions on a small multi-tenant infrastructure (a handful of servers, a dozen sites, several CMS engines). Methodology over specifics — every script and document uses generic `<TENANT>`, `<DOMAIN>`, `<INTERNAL_IP>` placeholders.

## Why this exists

Most "security checklist" content on the public internet is either marketing material or a giant unprioritised list. This repo is the opposite: a small, opinionated set of patterns that worked in practice, with the rationale ("why this and not that") preserved next to the code.

Each playbook captures:

- The **methodology** — how to think about the area, not just commands to run.
- A **template/script** with placeholders, MIT-licensed.
- The **anti-patterns** we hit so you don't have to.

## Contents

- [`security-audit/`](./security-audit/) — 8-phase remediation pattern that closed 27 findings with zero downtime in ~10 hours. Read-only audit → CVSS classification → phased fix → short async review per change.

## Conventions

- All paths in templates use generic placeholders: `<TENANT>`, `<DOMAIN>`, `<INTERNAL_IP>`, `<INTERNAL_PORT>`, `<APP_USER>`.
- Shell scripts are POSIX-ish bash (`set -euo pipefail`), tested on Debian/Ubuntu LTS.
- Comments explain "why", not "what". The "what" is in the next line of code.

## License

MIT — see [LICENSE](./LICENSE). Use freely, attribution appreciated.

## Maintainer

Open methodology playbooks. Issues and PRs welcome.
