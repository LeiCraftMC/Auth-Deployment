# LeiCraft_MC Auth deployment

One image with everything LeiCraft_MC Auth runs ([Dockerfile](docker/Dockerfile)):

| Process | Port | Source |
| --- | --- | --- |
| Zitadel | 8080 | `ghcr.io/zitadel/zitadel:<ZITADEL_VERSION>` |
| Zitadel login, LeiCraft_MC theme | 12192, under `/ui/v2/login` | upstream `apps/login` at the same tag, built with [login/overrides](login/README.md) |
| LAVIAC | 12191 | `gcr.leicraftmc.de/leicraftmc/auth/laviac:latest` |

```sh
docker build -t lcmc-auth .
```

supervisord ([docker/conf/services.ini](docker/conf/services.ini)) runs all three and restarts one
that exits. All output goes to the container log, and supervisord logs every start and exit by
process name. `docker exec <container> supervisorctl status` shows their state. The health check
probes all three. The login and LAVIAC run on Bun. All three run as the same non-root user,
`leicraftmc` (uid/gid 10001).

## Command

Zitadel always runs as `start-from-init --masterkeyFromEnv --tlsMode external`
([docker/conf/services.ini](docker/conf/services.ini)). Container arguments are not used. TLS
terminates at the reverse proxy, and the health check expects Zitadel to speak plain HTTP.

## Routing (reverse proxy in front)

- Each instance domain (e.g. `auth.leicraftmc.de`): `/ui/v2/login/*` goes to port 12192, everything
  else to port 8080. Zitadel needs HTTP/2 cleartext (h2c) for gRPC. Keep the original `Host` header,
  or send `x-zitadel-public-host` / `x-zitadel-instance-host`.
- LAVIAC's domain (e.g. `laviac.leicraftmc.de`): port 12191.

## Configuration

All configuration comes from environment variables.

- **Zitadel:** the usual `ZITADEL_*` settings: master key (`ZITADEL_MASTERKEY`), database, external
  domain, and the system API users for the login and LAVIAC. Enable Login V2 with the base URI
  `https://<domain>/ui/v2/login`.
- **Login:** the variables of the Zitadel login image, each prefixed with `LCMC_AUTH_LOGIN_`:
  `LCMC_AUTH_LOGIN_AUDIENCE`, `LCMC_AUTH_LOGIN_SYSTEM_USER_ID`,
  `LCMC_AUTH_LOGIN_SYSTEM_USER_PRIVATE_KEY` or `LCMC_AUTH_LOGIN_SYSTEM_USER_PRIVATE_KEY_FILE`, and
  `LCMC_AUTH_LOGIN_ZITADEL_SESSION_COOKIE_SECRET` (at least 32 characters).
  [docker/scripts/run-login.sh](docker/scripts/run-login.sh) removes the prefix and starts the login with only
  these, so it doesn't see any other variable of the container. `LCMC_AUTH_LOGIN_ZITADEL_API_URL`
  defaults to the Zitadel in the container (`http://localhost:8080`). `LCMC_AUTH_LOGIN_PORT`
  changes the port.
- **LAVIAC:** the `LAVIAC_*` variables of its `example.env`. Its data and config directories are
  volumes: `/opt/leicraftmc/auth/laviac/data` (SQLite) and `/opt/leicraftmc/auth/laviac/config`
  (e.g. `system-user.pem`). Bind-mounted host directories must be writable by uid 10001.

## Updating

- **Zitadel and the login:** `ARG ZITADEL_VERSION` in the [Dockerfile](docker/Dockerfile), then follow
  [login/README.md](login/README.md#upgrading-zitadel).
- **LAVIAC:** comes from its `latest` image at build time.
