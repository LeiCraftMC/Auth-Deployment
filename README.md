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

Zitadel's docs call the schema step `init schema`. No release has that name yet (up to v4.20.0;
it is on Zitadel's main branch, with `zitadel` kept as an alias), and up to v4.20.0
`init schema` runs the full init. `init zitadel` works on both.

## Routing (reverse proxy in front)

- Each instance domain (e.g. `auth.leicraftmc.de`): `/ui/v2/login/*` goes to port 12192, everything
  else to port 8080. Zitadel needs HTTP/2 cleartext (h2c) for gRPC. Keep the original `Host` header,
  or send `x-zitadel-public-host` / `x-zitadel-instance-host`.
- LAVIAC's domain (`laviac.int.leicraftmc.de`): port 12191.
- LAVIAC's claims webhook, `/api/v1/hooks/` on port 12191: Zitadel calls it for every token, so it
  needs a public URL even when the dashboard is internal. Zitadel refuses targets on localhost and
  private IPs. Set the URL in `LAVIAC_ZITADEL_CLAIMS_WEBHOOK_URL` if it isn't on LAVIAC's domain.

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

## Zitadel actions

LAVIAC answers the Zitadel actions itself: its claims webhook ([Token claims](#token-claims)),
whose target it keeps on every instance and syncs at startup and every 6 hours (see its
`example.env`). Left over from before:

- [actions/claims](actions/claims/README.md) (**deprecated**): the same claims as a PHP script on
  a separate web server. Not deployed anymore: `auth.leicraftmc.de` runs on LAVIAC's webhook.

### Token claims

The webhook adds these claims to the ID token, the userinfo response and JWT access tokens, built
from what Zitadel only sends in its own formats:

| Claim | Value | When |
| --- | --- | --- |
| `urn:lcmc-auth:username` | The plain username (`alice`). `preferred_username` stays `alice@<org domain>`, because the domain policy "User login must be on domain" stays on. With it on, usernames are only unique within an org: two orgs can each have an `alice`. | The app requests the `profile` scope. |
| `urn:lcmc-auth:roles` | The role keys in the app's own project as a list (`["devops", "infra-admin"]`), from Zitadel's `urn:zitadel:iam:org:project:roles`. | Zitadel sends roles: the project has "Assert roles on authentication" on, or the app asks for them by scope. |
| `urn:lcmc-auth:project-roles` | `<project id>:<role key>` for every project whose roles Zitadel sends (`["395838505755869195:devops", "400000000000000001:superadmin"]`), from Zitadel's `urn:zitadel:iam:org:project:<id>:roles`. | As above. Other projects only when the app asks for them (see below). |

Zitadel doesn't send the requested scopes to actions. The webhook goes by what Zitadel already put
in the userinfo: `preferred_username` only with `profile`, the roles claims only when roles are
asserted or requested. Apps that read claims from the ID token, not from the userinfo endpoint,
need "User Info inside ID Token" (for the username) and "User roles inside ID Token" (for the
roles) on.

Why the claims look like this:

- **Namespaced names.** Zitadel drops an action's claim when it has already set that key, and
  keeps names to itself: everything under `urn:zitadel:iam`, and from v5 (on Zitadel's main
  branch, not in v4.20.0) `groups`, filled with the names of Zitadel's user groups. Any org admin
  can create such a group, under any name.
- **Projects kept apart.** The same role key can mean different things in two projects, so
  `roles` holds the app's own project only, and `project-roles` names the project in every entry.
  Plain and qualified entries never share a claim, so no role key can pass for another project's
  role.
- **The project id is the separator's guarantee.** Zitadel allows any character in a role key
  (`:`, `/`, `|`, spaces, anything up to 200 characters), so no separator character is safe on
  its own. The project id is: it comes first and never holds a `:` (Zitadel's own ids are digits),
  so the first `:` ends it, whatever the role key holds. `395838505755869195:termix:admin` is the
  role `termix:admin`. Apps compare whole entries, or match a project with the prefix
  `<project id>:`, which can't match another project. A project created with a custom id that
  contains a `:` (the v2 API allows that) is left out of `project-roles`.

Configuring apps; most only need `urn:lcmc-auth:roles`:

- **Termix:** Group Claim `urn:lcmc-auth:roles`, Admin Group `<role key>`.
- **Grafana:** `groups_attribute_path = "urn:lcmc-auth:roles"[*]` and
  `role_attribute_path = contains("urn:lcmc-auth:roles"[*], '<role key>') && 'Admin' || 'Viewer'`.
  JMESPath needs the claim name in double quotes. Keep the `[*]`: `grafana.ini` strips quotes
  around a whole value.
- **Portainer Business Edition:** team claim `urn:lcmc-auth:roles`.

For roles from another project, for example a super admin role, the app requests the scopes
`urn:zitadel:iam:org:projects:roles` and `urn:zitadel:iam:org:project:id:<project id>:aud`, and
checks `urn:lcmc-auth:project-roles` for `<project id>:<role key>`. In Grafana:

```
(contains("urn:lcmc-auth:roles"[*], 'grafana-admin') || contains("urn:lcmc-auth:project-roles"[*], '<project id>:superadmin')) && 'Admin' || 'Viewer'
```

To accept only roles granted by one org (not through a project grant to another org), the app
also requests `urn:zitadel:iam:org:roles:id:<org id>`; Zitadel then sends only those.

Where an app makes the username its account key (Portainer's "User identifier", for example),
use `sub` instead, or let only one org's users in with the scope `urn:zitadel:iam:org:id:<org id>`.

## Updating

- **Zitadel and the login:** `ARG ZITADEL_VERSION` in the [Dockerfile](docker/Dockerfile), then follow
  [login/README.md](login/README.md#upgrading-zitadel).
- **LAVIAC:** comes from its `latest` image at build time.
