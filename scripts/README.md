# Scripts

## `health-check.sh`

Checks the production site:

```bash
bash scripts/health-check.sh
```

Optional environment variables:

```bash
DOMAIN=takedaclinic-shinjuku.jp
CERT_WARN_DAYS=30
HEALTHCHECK_WEBHOOK_URL=https://example.com/webhook
```

If `HEALTHCHECK_WEBHOOK_URL` is unset, failures are printed with a TODO instead of sending a notification.

## `inject-ga4.sh`

After a GA4 property is created, inject the Measurement ID into all production HTML files under `dist/`.

```bash
bash scripts/inject-ga4.sh G-XXXXXXXXXX
```

The script replaces the block between:

```html
<!-- GA4_BEGIN -->
<!-- GA4_END -->
```

It is safe to run again with the same or a different Measurement ID.

Rollback:

```bash
cd dist
git checkout -- index.html kenshin.html vaccination.html recruit.html 404.html
```

Do not create or guess a GA4 Measurement ID in code. Use the ID from the GA4 property created under the approved Google account.
