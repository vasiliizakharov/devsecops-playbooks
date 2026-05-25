# nginx `add_header` inheritance — the gotcha and the fix

## The gotcha

If a `location {}` block contains **any** `add_header` directive, the headers from the parent `server {}` (and `http {}`) are **not inherited**. They are silently dropped for that location.

This means HSTS, CSP, X-Frame-Options — anything set at server level — disappears the moment you add even a single header inside a sensitive `location`. The result: cache headers work, but security headers vanish from exactly the URLs you cared most about.

## How to spot it

```bash
# Compare server-root vs a sensitive location
curl -sI https://<DOMAIN>/ | grep -iE 'strict-transport-security|content-security-policy'
curl -sI https://<DOMAIN>/<sensitive-path>/ | grep -iE 'strict-transport-security|content-security-policy'
```

If the second is missing what the first has, you have the bug.

## The fix — single-include pattern

Pull all security headers into one snippet and include it both at `server` level and inside every `location` that adds its own headers.

```nginx
# /etc/nginx/snippets/security-headers.conf
add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
add_header Content-Security-Policy "default-src 'self'; img-src 'self' data: https:; style-src 'self' 'unsafe-inline'" always;
add_header X-Frame-Options "DENY" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
add_header Permissions-Policy "geolocation=(), microphone=(), camera=()" always;
add_header X-Content-Type-Options "nosniff" always;
```

```nginx
# /etc/nginx/sites-enabled/<DOMAIN>.conf
server {
    listen 443 ssl http2;
    server_name <DOMAIN>;

    include snippets/security-headers.conf;

    location ~* \.(jpg|jpeg|png|gif|svg|webp|woff2?)$ {
        expires 30d;
        add_header Cache-Control "public, immutable";
        include snippets/security-headers.conf;   # <-- crucial
    }

    location /api/ {
        proxy_pass http://<INTERNAL_IP>:<INTERNAL_PORT>;
        add_header X-Request-ID $request_id always;
        include snippets/security-headers.conf;   # <-- crucial
    }
}
```

Note the `always` modifier. Without it, headers are only set on 200/201/204/301/302/303/304/307/308 responses — error pages would leak without it.

## Verify

```bash
# loop over every URL in your sitemap and confirm HSTS is present
for url in $(curl -s https://<DOMAIN>/sitemap.xml | grep -oP '(?<=<loc>)[^<]+'); do
  printf "%s  " "$url"
  curl -sI "$url" | grep -iE '^strict-transport-security' >/dev/null && echo OK || echo MISSING
done
```

Expect 100% `OK`. Anything `MISSING` is a candidate for finding-the-`add_header`-block-that-broke-inheritance.

## Why nginx does this

The `add_header` directive is implemented in the `ngx_http_headers_filter_module`. The module stores headers per-config-block. When evaluating, it walks up from the innermost matched location — and stops at the first level that has `add_header` defined. This is documented behavior, not a bug:

> There could be several add_header directives. These directives are inherited from the previous configuration level if and only if there are no add_header directives defined on the current level.

That last clause is what trips most operators. The right mental model: `add_header` is **replace**, not **merge**.
