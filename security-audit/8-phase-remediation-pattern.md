# 8-Phase Security Remediation Pattern

A deeper write-up of the methodology that drove a single-day remediation session: 27 findings closed, zero downtime, one residual LOW deferred to the following week.

## Phase 0 — Read-only audit

Six probe areas, all observational. Nothing should change on disk during this step.

| Area | What to look at | Common pitfalls |
|---|---|---|
| SSH | `sshd_config`: `PermitRootLogin`, `PasswordAuthentication`, `MaxAuthTries`, `AllowUsers`/`AllowGroups`. `lastlog -b 60` for dormant accounts. | `PermitRootLogin yes` left from initial provisioning. |
| TLS / HTTP headers | `curl -I` against representative URLs. HSTS, CSP, XFO, Referrer-Policy, Permissions-Policy. | `add_header` not inherited into `location` blocks — see `canonical-patterns/nginx-add-header-inheritance.md`. |
| Exposed paths | `curl -sk -o /dev/null -w '%{http_code}\n' <url>` against a path list: `.git/HEAD`, `.env`, `composer.json`, `wp-config.bak`, `phpinfo.php`, `/server-status`. | "It's not linked anywhere" is not a protection. |
| CMS-specific | `/wp-json/wp/v2/users` user enum, default admin slug, XML-RPC, missing IP allowlist on `/wp-admin`. | REST API leaks usernames even on hardened sites unless filtered. |
| DB exposure | `ss -tlnp` for 0.0.0.0 listeners. `pg_hba.conf` / MySQL `user` table for `trust`/`%` patterns. | A `host all all 0.0.0.0/0 trust` line surviving from a migration. |
| Secrets & DNS | `find <webroots> -name '.env' -perm /004`. `dig +short axfr @<ns> <zone>`. SPF/DKIM/DMARC alignment. | World-readable `.env`. Open AXFR. SPF with `+all`. |

Output: a table of findings. We use this schema:

```
| ID | Severity | Area | Domain/Host | Finding | Evidence | Recommendation |
```

## CVSS-ish severity classes

| Class | Meaning | Typical content |
|---|---|---|
| CRITICAL | Direct path to data exposure or RCE; minutes to abuse. | Default web terminal without auth; world-writable secret; auth-bypass parameter. |
| HIGH | Significant attack surface that elevates risk by an order of magnitude. | AXFR open; REST user enum; admin panel exposed to the internet. |
| MEDIUM | Hardening gap; requires a chain or a user mistake. | HSTS missing on a section; nginx header not inherited; AppArmor profile gap. |
| LOW | Best-practice deviation, no concrete attack scenario known. | Outdated TLS cipher order; verbose `server` token; SPF `~all` vs `-all`. |

## Phase 1 — CRITICAL

Run first because the blast radius of the fix is small (delete / chmod / nginx-deny) but the blast radius of the bug is enormous. Examples:

- Default CMS web terminal (adminer/pma/wp-cli web) without an auth gate. Remediation: physically delete + nginx `deny` + WAF rule.
- World-readable secrets in webroot. Remediation: move to `/etc/<app>/`, `chmod 0640`, set `group=<app_user>`, drop the symlink, nginx `deny /*.env`.
- World-writable backup config. Remediation: `chmod 0600`, root-own, checksum verification on load.

No service restarts. `nginx -s reload` is fine, but no `systemctl restart anything`.

## Phase 2 — HIGH

- DNS AXFR open: add `allow-transfer { <slave-ip>; }` + TSIG.
- WP REST API user enumeration: mu-plugin filters `users` endpoint to 401 for anonymous.
- Orphan debug HTTP servers: `systemctl stop` + iptables drop + `find /etc/systemd/system -name '*.service' -exec grep -lE 'python.*http\.server|busybox httpd' {} +`.

## Phase 3-4 — MEDIUM and DNSSEC

See:
- `canonical-patterns/nginx-add-header-inheritance.md`
- `canonical-patterns/bind-dnssec-cds-cdnskey.sh`

**Key insight on DNSSEC**: RFC 8078 ("Managing DS Records from the Parent via CDS/CDNSKEY") lets you publish your own DS-record updates inside your zone. The parent (registrar) periodically pulls them and applies. This replaces the manual "open a ticket, paste a DS, wait" workflow that historically made DNSSEC rollovers risky.

## Phase 5-6 — Defence-in-depth: CMS + SSH/IAM

**WP admin two-layer**: layer 1 is nginx IP allowlist (`allow <office-cidr>; deny all;`), layer 2 is Basic-Auth inside the same location. One layer can fail (VPN leak, proxy chain) and the other still holds. See [`examples/basic-auth-deployment.sh`](./examples/basic-auth-deployment.sh).

**Dormant users**: `lastlog -b 60 | awk 'NR>1 && $2!="**Never" {print $1}'` lists candidates. `usermod -L <user>` locks the password but keeps key-based sudo. Reverse with `usermod -U <user>`.

**SSH hardening**:

```
PermitRootLogin prohibit-password
PasswordAuthentication no
MaxAuthTries 3
LoginGraceTime 20
AllowGroups ssh-users
Banner /etc/issue.net
```

Always `sshd -t` before `systemctl reload sshd`. A syntax error + immediate reload kicks every active session AND blocks new logins until someone has console access.

## Phase 7-8 — Service-level + PHP-FPM

**Unused daemons**: `proftpd` (port 21), `rsync --daemon` (port 873), `telnetd`, `nfsd` if not used.
```
systemctl stop <unit> && systemctl disable <unit>
apt-mark hold <package>   # do not purge — keeps config for forensic value
```

**PHP-FPM major version migration zero-downtime**: see [`examples/php-fpm-major-version-migration.sh`](./examples/php-fpm-major-version-migration.sh). The summary: two pools running side by side, atomic `fastcgi_pass` flip in nginx, `nginx -s reload` (does not kill workers), old pool kept warm for one week.

## Short async review per change

Short async review per change. Template:

```
Change: <one-line summary>
Blast radius: <which hosts / sites / users affected>
Rollback plan: <how to undo in <2 min>
Test plan: <smoke URLs / commands>

Approval (timestamped):
```

The point is not "more bureaucracy". It is to catch the *one perspective* that would have spotted the issue: a usability concern about Basic-Auth on a customer-facing booking page; a compliance concern about audit-log retention shorter than the regional law-mandated minimum.

## Eight anti-patterns to remember

1. Single-source-of-truth violation: the same credential in three places (env / code / vault), synchronised by hand.
2. Default web terminals on production without an auth gate.
3. `nginx add_header` without understanding inheritance.
4. SSH `MaxAuthTries 6` (default) combined with weak user passwords.
5. DNS AXFR without an ACL — entire internal naming exposed.
6. World-writable backup config — single point of failure for recoverability.
7. Service files without `ProtectSystem=` / `PrivateTmp=` — extra blast radius if compromised.
8. `*.bak` / `*.old` / `*.orig` in the webroot — forgotten file versions with outdated but still valid secrets.

## Outcome we observed

| Metric | Value |
|---|---|
| Findings at the start | 27 |
| Residual risk at end of day | 1 LOW (scheduled next week) |
| Session length | ~10 hours |
| Planned downtime windows | 0 |
| Actual downtime | 0 |
| Services reloaded without disruption | 6 |
| Bak-files swept into obfuscated archive | 41 |

The session ran on a small production estate. Your mileage will vary with scale, but the chain — read-only audit → classification → short async review → phased remediation — scales linearly with finding count.
