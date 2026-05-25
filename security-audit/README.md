# Security audit — 8-phase remediation playbook

A read-only-first methodology to take an audit-finding backlog from "27 unknown unknowns" to "1 LOW item scheduled for next week" in a single working day, with zero user-visible downtime.

## Quick orientation

| Doc | Purpose |
|---|---|
| [`8-phase-remediation-pattern.md`](./8-phase-remediation-pattern.md) | The full methodology — six audit areas, eight remediation phases, short async review per change. |
| [`audit-checklist.sh`](./audit-checklist.sh) | Read-only audit script. Outputs a markdown report. Idempotent. |
| [`canonical-patterns/`](./canonical-patterns/) | Specific anti-patterns and their fixes (one file per topic). |
| [`examples/`](./examples/) | End-to-end fix examples (Basic-Auth deployment, PHP-FPM major-version migration). |

## TL;DR — the chain

1. **Read-only audit** across six areas: SSH, TLS/headers, exposed paths, CMS-specific, DB exposure, secrets & DNS.
2. **Classify** every finding by CVSS-ish severity: CRITICAL / HIGH / MEDIUM / LOW.
3. **Remediate in phases** — CRITICAL first, never touch a higher-severity later phase before all lower-numbered phases close.
4. **Short async review per change** via template: what changed / blast radius / rollback plan / approval.
5. **Post-remediation verification** via the same read-only audit script. Findings should drop to zero or have an explicit "deferred" reason.

## What this is **not**

- Not a pentest. We are not exploiting — we are observing and remediating.
- Not a compliance checklist. We follow the spirit of common frameworks (CIS, OWASP, NIST) without binding to any one.
- Not a tool. It is a methodology with templates. Bring your own ticket system, your own monitoring, your own change-management.

## Why phases matter

Closing CRITICALs first is not only about risk — it is also about *blast radius management*. CRITICALs are usually low-blast-radius fixes (delete a file, deny a path, chmod a credential). HIGH/MEDIUM fixes typically touch live config (nginx, DNS, SSH) and require careful review and a rollback story. By the time you reach the touchy bits, the easy wins are already banked.

## Compatible with

- Debian/Ubuntu LTS (apt-based)
- nginx 1.18+
- BIND 9.16+ for DNSSEC patterns
- PHP-FPM 7.4+ for the major-version migration example
- A `sudo`-capable account with permission to read system config but not necessarily root login
