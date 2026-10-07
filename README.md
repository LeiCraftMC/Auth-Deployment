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

Zitadel starts through [docker/scripts/run-zitadel.sh](docker/scripts/run-zitadel.sh). Container
arguments are not used. TLS terminates at the reverse proxy, and the health check expects Zitadel
to speak plain HTTP.

`LCMC_AUTH_ZITADEL_INITMODE` decides how the database is prepared. Both modes run on every start
and leave an already prepared database as it is.

| Mode | Runs | Database |
| --- | --- | --- |
| `auto` (default) | `start-from-init --masterkeyFromEnv` | Zitadel creates its user, the database and the grants with the Postgres admin login (`ZITADEL_DATABASE_POSTGRES_ADMIN_*`). |
| `manual` | `init zitadel`, then `start-from-setup --masterkeyFromEnv` | The user and the database exist already, and the user may create schemas in the database: it owns it, or has `GRANT ALL ON DATABASE <db> TO <user>`. Zitadel only creates its schemas and tables, with the service user (`ZITADEL_DATABASE_POSTGRES_USER_*`). No admin login is needed. |

Zitadel's docs call the schema step `init schema`. That name only exists after v4.19.4, and on
v4.19.4 `init schema` runs the full init. `init zitadel` works on both.

## Routing (reverse proxy in front)

- Each instance domain (e.g. `auth.leicraftmc.de`): `/ui/v2/login/*` goes to port 12192, everything
  else to port 8080. Zitadel needs HTTP/2 cleartext (h2c) for gRPC. Keep the original `Host` header,
  or send `x-zitadel-public-host` / `x-zitadel-instance-host`.
- LAVIAC's domain (e.g. `laviac.leicraftmc.de`): port 12191.

## Configuration

All configuration comes from environment variables.

- **Zitadel:** the master key in `LCMC_AUTH_ZITADEL_MASTERKEY` (or `ZITADEL_MASTERKEY` if that is
  unset), `LCMC_AUTH_ZITADEL_INITMODE` (`auto` or `manual`, see [Command](#command)), and the usual
  `ZITADEL_*` settings: database, external domain, and the system API users for the login and
  LAVIAC. Enable Login V2 with the base URI `https://<domain>/ui/v2/login`.
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
