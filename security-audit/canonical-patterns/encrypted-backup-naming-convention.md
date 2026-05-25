# encrypted backup bundle naming convention — obfuscated backup pattern

A naming convention for offline backup bundles that prevents simple bucket-listing attacks from leaking who or what is being backed up.

## Why obfuscate?

If your backups are stored in S3-compatible storage with a list-bucket permission anywhere in the chain (intentional or accidental), an attacker who enumerates objects gets:

```
2026-05-20T12:00:00Z/<tenant-name>-mysql-full.sql.gz.age
2026-05-20T12:00:00Z/<tenant-name>-webroot.tar.gz.age
```

That's already significant intel: "this tenant exists, this is the backup schedule, the data type, and the size of their content". Even though the contents are encrypted (`.age`), the metadata leaks.

## The convention

```
<encrypted-archive-store-timestamp>-<sha256-prefix>.bin
```

Where:
- `<encrypted-archive-store-timestamp>` is `YYYYMMDDTHHMMSSZ` (ISO 8601 Z-suffix, no separators) — sortable, regex-easy.
- `<sha256-prefix>` is the first 16 hex chars of `sha256("<tenant>-<artifact>-<encrypted-archive-store-timestamp>" + tenant-pepper)`.
- `.bin` is the universal extension — gives away no content type.

Example:
```
20260525T093014Z-68ed69f4e31d5214.bin
20260525T093014Z-d5c6fe1c70d45de0.bin
```

You cannot tell which file is whose data, what content type it is, or even whether two files in the same upload belong to the same tenant.

## Recipient and key

- Encryption: [age](https://github.com/FiloSottile/age) with public keys. Backups are encrypted in transit and at rest.
- Each tenant has a separate recipient key. Recipient public keys live in `/etc/encrypted-archive-store/<tenant>.pub` on the source host (mode 0644 ok — these are public).
- The matching private keys are held offline on the recovery operator's hardware token.

## Manifest

To allow recovery, a separate **manifest file** stores the mapping:

```
20260525T093014Z-MANIFEST.bin.age
```

The manifest itself is age-encrypted (recipient = operator only) and contains JSON:

```json
{
  "timestamp_iso": "2026-05-25T09:30:14Z",
  "tenant_pepper_hash": "...",
  "artifacts": [
    {
      "sha256_prefix": "68ed69f4e31d5214",
      "tenant": "<tenant-1>",
      "kind": "webroot",
      "original_path": "/var/www/<tenant-1>/",
      "size": 1131000000,
      "sha256_full": "..."
    }
  ]
}
```

Recovery flow:
1. Operator decrypts the manifest with their offline key.
2. From the manifest, picks the `sha256_prefix` of the artifact they want.
3. Pulls that single `.bin` file from offsite.
4. Decrypts with the tenant recipient key (also offline-held).

The result: even if storage is enumerated, an attacker sees opaque, identically-formatted blobs with no actionable metadata.

## Anti-pattern

Do NOT embed tenant or content type into the filename "for convenience" — that defeats the entire point. Use the manifest.
