# Clean username claim

[zitadel-claim.php](zitadel-claim.php) is a Zitadel Actions v2 target. It adds a `username` claim
with the plain username to the ID token and the userinfo response. `preferred_username` stays
`username@orgdomain`, because the domain policy "User login must be on domain" stays on.

The claim is only added when the client requests the `profile` scope. Zitadel doesn't send the
requested scopes to actions, so the script checks for `preferred_username` in the userinfo, which
Zitadel only fills when `profile` was requested.

It runs outside the image, on a PHP web server (PHP 8 or later). It is deployed at
`https://auth.is-on.net/intactions/zitadel-claim.php`.

Instances that LAVIAC provisions don't need it: their template adds the target
`laviac-username-claim`, which calls LAVIAC's own webhook and gives the same claim (see
`LAVIAC_ZITADEL_USERNAME_CLAIM` in LAVIAC's `example.env`). This script is for instances LAVIAC
didn't provision, like `auth.leicraftmc.de`.

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
ID Token" on. Otherwise the ID token has no profile claims, and the script adds no `username`.

## Calling the API with the system user

The target and the execution can be managed with the system API user (`laviac-system-user`). The
`aud` of its JWT must be Zitadel's external domain, `https://auth.is-on.net`, not the instance
domain. Any other audience gets `401 Errors.Token.Invalid (AUTH-7fs1e)`. Send the requests to the
instance domain (`https://auth.leicraftmc.de`) so Zitadel picks that instance.
