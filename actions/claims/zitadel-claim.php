<?php
// DEPRECATED: LAVIAC's built-in claims webhook (target `laviac-claims`) gives the same claims.
// Only kept until auth.leicraftmc.de is switched over; see README.md next to this file.
//
// Zitadel Actions v2 target for the function preuserinfo (see README.md next to this file).
// Adds claims built from Zitadel's own, the same as LAVIAC's server/lib/zitadel/claims.ts:
// - "urn:lcmc-auth:username": the plain username (preferred_username stays username@orgdomain).
//   Only when the "profile" scope was requested: Zitadel sends no scopes to actions, but it only
//   puts preferred_username into the userinfo when profile was requested.
// - "urn:lcmc-auth:roles": the role keys of urn:zitadel:iam:org:project:roles, the app's own
//   project, whenever Zitadel sends roles.
// - "urn:lcmc-auth:project-roles": "<project id>:<role key>" from every
//   urn:zitadel:iam:org:project:<id>:roles claim.
// Roles of different projects are never merged: the same key can mean different things in two
// projects. The names are namespaced: Zitadel drops an action's claim whose key it already set,
// and Zitadel v5 sets "groups" from its own user groups.

const MAX_AGE = 300; // seconds a signed request stays valid

// Signing key of the target in Zitadel. Never commit it; set it in the web server or PHP-FPM pool.
$signingKey = getenv('ZITADEL_ACTION_SIGNING_KEY') ?: ($_SERVER['ZITADEL_ACTION_SIGNING_KEY'] ?? '');
if ($signingKey === '') {
	http_response_code(500);
	exit;
}

$body = file_get_contents('php://input');

// ZITADEL-Signature: t=<unix time>,v1=<hex HMAC-SHA256 of "<t>.<body>">. While a regenerated key is
// in its grace period, Zitadel sends one v1 per key.
$parts = [];
foreach (explode(',', $_SERVER['HTTP_ZITADEL_SIGNATURE'] ?? '') as $pair) {
	[$k, $v] = array_pad(explode('=', trim($pair), 2), 2, '');
	$parts[$k][] = $v;
}
$t = $parts['t'][0] ?? '';
$valid = false;
if (ctype_digit($t) && abs(time() - (int) $t) <= MAX_AGE) {
	$expected = hash_hmac('sha256', $t . '.' . $body, $signingKey);
	foreach ($parts['v1'] ?? [] as $sig) {
		if (hash_equals($expected, $sig)) {
			$valid = true;
			break;
		}
	}
}
if (!$valid) {
	http_response_code(401);
	exit;
}

$req = json_decode($body, true) ?? [];
$userinfo = is_array($req['userinfo'] ?? null) ? $req['userinfo'] : [];
$claims = [];

// username
if (!empty($userinfo['preferred_username'])) {
	$username = $req['user']['username'] ?? '';
	$domain = $req['org']['primary_domain'] ?? '';
	// The username normally has no domain; strip "@<org primary domain>" in case it was created with one.
	if ($domain !== '' && str_ends_with(strtolower($username), '@' . strtolower($domain))) {
		$username = substr($username, 0, -strlen($domain) - 1);
	}
	if ($username !== '') {
		$claims[] = ['key' => 'urn:lcmc-auth:username', 'value' => $username];
	}
}

// roles: the app's own project
$own = $userinfo['urn:zitadel:iam:org:project:roles'] ?? null;
if (is_array($own) && $own) {
	// PHP turns numeric keys into ints; role keys are strings.
	$roles = array_map('strval', array_keys($own));
	sort($roles, SORT_STRING);
	$claims[] = ['key' => 'urn:lcmc-auth:roles', 'value' => $roles];
}

// project-roles: every project, with its id. Project ids are digits, so the first ":" ends the id
// whatever the role key holds.
$projectRoles = [];
foreach ($userinfo as $claim => $value) {
	if (is_array($value) && preg_match('/^urn:zitadel:iam:org:project:(\d+):roles$/', (string) $claim, $m)) {
		foreach (array_keys($value) as $role) {
			$projectRoles[] = $m[1] . ':' . $role;
		}
	}
}
if ($projectRoles) {
	sort($projectRoles, SORT_STRING);
	$claims[] = ['key' => 'urn:lcmc-auth:project-roles', 'value' => $projectRoles];
}

header('Content-Type: application/json');
echo $claims ? json_encode(['append_claims' => $claims]) : '{}';
