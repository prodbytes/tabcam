# tabscan_floci

Runs [Floci](https://floci.io/), a local AWS emulator, as the TabScan
**CloudFront** distribution, over HTTP and HTTPS. Like the deployed
CloudFront ([tabscan_infra/site.yaml](../tabscan_infra/site.yaml)), it only
routes. The index and the app keep running on their own dev servers:

| Path | Origin |
|------|--------|
| default (`/`, anything else) | `tabscan_index`, Python `http.server` (`INDEX_PORT`, 2013): `/` redirects to `/app/` |
| `/app*` | Flutter dev server, `flutter run -d web-server --base-href /app/` (`FLUTTER_WEB_PORT`, 2012) |

Open **https://local.tabscan.nu01.com:2443/app/**, or over HTTP
**http://tabscan.localhost:2014/app/**. Browsers and curl resolve
`*.localhost` to loopback, so no hosts-file edit is needed.

CloudFront forwards paths as is (it can't strip a prefix), so each origin
serves its own prefix: the app has the `/app/` base href.

## Files

| Path | Holds |
|------|-------|
| [compose.yaml](compose.yaml) | The `tabscan-floci` container, bound to 127.0.0.1 |
| [init/ready.d/10-cloudfront.sh](init/ready.d/10-cloudfront.sh) | Ready hook: creates the cache policy, origin request policy and distribution |
| `certs/` (git-ignored) | The local HTTPS certificate and key, from [scripts/local-certs.sh](../scripts/local-certs.sh) |

## How it works

- `devbox services up` starts it as `4-floci`. The process is ready once
  Floci reports its `ready` hooks done (`/_floci/init`).
- Storage is `memory`, so every start is clean and the hook recreates the
  distribution. The distribution ID changes each time; use the alias.
- Nothing is cached (all TTLs are 0). Every viewer header except `Host`, plus
  all cookies and query strings, is forwarded, matching AWS's managed
  `AllViewerExceptHostHeader` policy. Floci doesn't model AWS managed
  policies, so the hook creates an equivalent. All methods are allowed.
- **Hot reload works through the CDN URL.** The Flutter dev server writes
  the `Host` it receives into its debug-channel WebSocket URL. Floci can't
  carry WebSockets (it drops `Upgrade`), so that channel mustn't go through
  it. Both origins are therefore named `dev.tabscan.localhost`:
  - Inside the container, compose maps it to the Docker host
    (`host-gateway`), and it's allowlisted as a private origin
    (`FLOCI_SERVICES_CLOUDFRONT_ALLOWED_PRIVATE_ORIGIN_HOSTS`).
  - In the browser, it's loopback, so the page's
    `ws://dev.tabscan.localhost:2012/app/$dwdsSseHandler` goes straight to
    the dev server.
- The image is a dated nightly (`nightly-09242026-compat`), pinned by
  digest in `compose.yaml`, the same one presence uses: Floci 2.1.0 forwards
  no viewer headers at all to custom origins. Move to the next release once
  it ships, with its digest
  (`docker buildx imagetools inspect floci/floci:<tag>`).
- Inside the container Floci listens on 4566 (HTTP and HTTPS) and 8443
  (HTTPS); compose maps them to `FLOCI_PORT` (2014) and `FLOCI_HTTPS_PORT`
  (2443) on the host. Don't pass `FLOCI_PORT` into the container: Floci
  reads it as its own listen port, and the hook then can't reach it.
- The health monitor's `🚚 cdn` check requests `/app/` with the alias as
  the `Host` header.

## HTTPS

`local.tabscan.nu01.com` resolves to `127.0.0.1` and `::1` (A and AAAA
records in the Route 53 zone `nu01.com`, owned by the nu01 repository's
`nu01-dns` stack). It is the distribution's
second alias, for origins that need a public top-level domain, such as
Google sign-in's JavaScript origins.

- [scripts/local-certs.sh](../scripts/local-certs.sh) runs before Floci
  starts. It uses [mkcert](https://github.com/FiloSottile/mkcert) from
  devbox to write `certs/tabscan.pem` and `certs/tabscan-key.pem` for
  `local.tabscan.nu01.com`, `tabscan.localhost`, `*.tabscan.localhost`,
  `localhost`, `127.0.0.1` and `::1`. It regenerates them only when one of
  these is true:
  - they're missing;
  - they expire within 30 days;
  - they don't cover every name;
  - they weren't signed by this machine's mkcert CA.

  `certs/` is git-ignored.
- compose mounts `certs/` read-only and sets `FLOCI_TLS_ENABLED`,
  `FLOCI_TLS_CERT_PATH`, `FLOCI_TLS_KEY_PATH` and
  `FLOCI_TLS_AWS_HTTPS_PORT=8443`. 2443 on the host, rather than 443,
  avoids binding a privileged port.
- The certificate is signed by mkcert's local CA (`mkcert -CAROOT`). Each
  machine has one CA, shared by every project that uses mkcert. **To have
  browsers trust it, run once:** `devbox run mkcert -install`. It asks for
  your password, because it adds the CA to the system trust store. Until
  then, curl and the health check validate against the CA file directly,
  and browsers show a certificate warning.
- Hot reload still works over HTTPS. The dev server's `ws://` channel to
  `dev.tabscan.localhost` is allowed from an HTTPS page, because browsers
  treat `*.localhost` as a secure origin.
- The health monitor's `🔒 https` check fetches `/app/` over HTTPS and
  validates the certificate against mkcert's CA.

## Settings

| Variable | Default | Meaning |
|----------|---------|---------|
| `FLOCI_PORT` | `2014` | Host port for Floci (HTTP and HTTPS) |
| `FLOCI_HTTPS_PORT` | `2443` | Host port for Floci's HTTPS-only listener |
| `TABSCANNER_CDN_ALIAS` | `tabscan.localhost` | Distribution alias (host name to browse) |
| `TABSCANNER_PUBLIC_HOST` | `local.tabscan.nu01.com` | Second alias, with a public TLD; also in the certificate |
| `TABSCANNER_ORIGIN_HOST` | `dev.tabscan.localhost` | Origin host name: the Docker host inside the container, and loopback in the browser |

## Limitations

- **Linux outside the dev container:** the Flutter dev server and the
  index bind to 127.0.0.1. On plain Docker, `host-gateway` is the bridge
  address, which can't reach them (Docker Desktop on macOS forwards it to
  the host's loopback). Set `TABSCANNER_BIND_HOST=0.0.0.0`, as the dev
  container does, to have them listen on every interface.
- There's no edge caching (see the
  [Floci CloudFront docs](https://github.com/floci-io/floci/blob/main/docs/services/cloudfront.md)).
