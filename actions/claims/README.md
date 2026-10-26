# Standard claims (deprecated)

> **Deprecated.** LAVIAC has the same webhook built in: the target `laviac-claims`, which LAVIAC
> keeps on every instance of the Zitadel and which replaces this script's `clean-username-target`
> on its own. This script only stays until `auth.leicraftmc.de` is switched over (see
> [Switching to LAVIAC](#switching-to-laviac)), then it is removed.

[zitadel-claim.php](zitadel-claim.php) is a Zitadel Actions v2 target. It adds standard OIDC
claims to the ID token and the userinfo response, built from what Zitadel only sends in its own
formats:

| Claim | Value | When |
| --- | --- | --- |
| `username` | The plain username (`alice`). `preferred_username` stays `alice@<org domain>`, because the domain policy "User login must be on domain" stays on. | The app requests the `profile` scope. |
| `groups` | The user's role keys as a flat list (`["devops", "infra-admin"]`), from Zitadel's `urn:zitadel:iam:org:project:roles` and `urn:zitadel:iam:org:project:<id>:roles` claims. | Zitadel sends roles: the project has "Assert roles on authentication" on, or the app asks for them by scope. |

Zitadel doesn't send the requested scopes to actions. The script goes by what Zitadel already put
in the userinfo: `preferred_username` only with `profile`, the roles claims only when roles are
asserted or requested.

Apps read `groups` the usual way, for example Termix (Group Claim `groups`, Admin Group
`<role key>`), Grafana (`groups_attribute_path = groups`, `role_attribute_path` with
`contains(groups[*], '<role key>')`) or Portainer Business Edition (team claim `groups`).

It runs outside the image, on a PHP web server (PHP 8 or later). It is deployed at
`https://auth.is-on.net/intactions/zitadel-claim.php`.

## Switching to LAVIAC

1. Deploy LAVIAC with the claims webhook and `LAVIAC_ZITADEL_SYSTEM_API_AUDIENCE=https://auth.is-on.net`
   (LAVIAC reads each target's signing key through the system API).
2. Zitadel calls the webhook at `https://laviac.int.leicraftmc.de/api/v1/hooks/claims/<instance
   id>`, the default with `LAVIAC_APP_URL=https://laviac.int.leicraftmc.de`. That domain resolves
   to the server's public IP, which Zitadel accepts. Zitadel refuses targets on localhost and
   private IPs (`ZITADEL_HTTPCLIENT_DENYLIST`); keep that, or admins of any instance could point
   targets at internal services. So if the server's own resolver answers with a private address
   for that name, give the webhook another public URL in `LAVIAC_ZITADEL_CLAIMS_WEBHOOK_URL`.
3. LAVIAC switches the instances itself: 60 s after it starts (then every 6 hours) its
   `syncClaims` task adds `laviac-claims` to `preuserinfo` and `preaccesstoken` of every
   instance, and takes `clean-username-target` out of every execution and deletes it. It does
   that only once a signed test call through the webhook URL gets the claims back; until then
   the PHP target stays in place. The task's log is on LAVIAC's Tasks page ("Sync the claims
   webhook").
4. Log in to an app with the `profile` scope and check `username` and `groups`. Then delete this
   script from the web server.

## Deploying

1. Copy `zitadel-claim.php` to the web server.
2. Set `ZITADEL_ACTION_SIGNING_KEY` to the signing key of the target. Zitadel shows the key when
   the target is created or the key is regenerated. Never commit it. For example:
   - Apache: `SetEnv ZITADEL_ACTION_SIGNING_KEY <key>` in the vhost.
   - nginx with PHP-FPM: `fastcgi_param ZITADEL_ACTION_SIGNING_KEY <key>;`, or
     `env[ZITADEL_ACTION_SIGNING_KEY] = <key>` in the FPM pool.

   Without the key the script answers 500. A request without a valid `ZITADEL-Signature` gets
   401.

## Zitadel setup

On the instance (Actions v2):

| What | Setting |
| --- | --- |
| Target | `clean-username-target`, type REST call, endpoint as above, timeout 10s, interrupt on error off |
| Execution | condition: function `preuserinfo`, target: `clean-username-target` |

Don't attach the target to a request or response condition, such as the response of
`/zitadel.oidc.v2.OIDCService/CreateCallback`. On a response condition, Zitadel replaces the API
response with the target's answer. On `CreateCallback` that breaks every login.

Apps that read claims from the ID token, not from the userinfo endpoint, need "User Info inside
ID Token" (for `username`) and "User roles inside ID Token" (for `groups`) on. Otherwise the ID
token lacks the claims the script builds on, and it adds nothing there.

## Calling the API with the system user

The target and the execution can be managed with the system API user (`laviac-system-user`). The
`aud` of its JWT must be Zitadel's external domain, `https://auth.is-on.net`, not the instance
domain. Any other audience gets `401 Errors.Token.Invalid (AUTH-7fs1e)`. Send the requests to the
instance domain (`https://auth.leicraftmc.de`) so Zitadel picks that instance.
