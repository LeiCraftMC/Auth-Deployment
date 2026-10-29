# Claims script (deprecated)

> **Deprecated.** LAVIAC has the same webhook built in: the target `laviac-claims`, which LAVIAC
> keeps on every instance of the Zitadel and which replaces this script's `clean-username-target`
> on its own. `auth.leicraftmc.de` has been switched over (see
> [Switching to LAVIAC](#switching-to-laviac)); the script is not deployed anymore.

[zitadel-claim.php](zitadel-claim.php) is a Zitadel Actions v2 target. It adds the same claims
to the ID token and the userinfo response as LAVIAC's webhook: `urn:lcmc-auth:username`,
`urn:lcmc-auth:roles` and `urn:lcmc-auth:project-roles`. What they hold, and how apps use them, is
in [Token claims](../../README.md#token-claims).

It runs outside the image, on a PHP web server (PHP 8 or later). It was deployed at
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
4. Log in to an app with the `profile` scope and check `urn:lcmc-auth:username`,
   `urn:lcmc-auth:roles` and `urn:lcmc-auth:project-roles`. Then delete this script from the web
   server.

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
ID Token" (for the username) and "User roles inside ID Token" (for the roles) on. Otherwise the ID
token lacks the claims the script builds on, and it adds nothing there.

## Calling the API with the system user

The target and the execution can be managed with the system API user (`laviac-system-user`). The
`aud` of its JWT must be Zitadel's external domain, `https://auth.is-on.net`, not the instance
domain. Any other audience gets `401 Errors.Token.Invalid (AUTH-7fs1e)`. Send the requests to the
instance domain (`https://auth.leicraftmc.de`) so Zitadel picks that instance.
