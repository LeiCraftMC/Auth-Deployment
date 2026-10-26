<?php
// DEPRECATED: LAVIAC's built-in claims webhook (target `laviac-claims`) gives the same claims.
// Only kept until auth.leicraftmc.de is switched over; see README.md next to this file.
//
// Zitadel Actions v2 target for the function preuserinfo (see README.md next to this file).
// Adds standard claims built from Zitadel's own:
// - "username": the plain username (preferred_username stays username@orgdomain). Only when the
//   "profile" scope was requested: Zitadel sends no scopes to actions, but it only puts
//   preferred_username into the userinfo when profile was requested.
// - "groups": the role keys of Zitadel's roles claims (urn:zitadel:iam:org:project:roles and
//   urn:zitadel:iam:org:project:<id>:roles) as a flat list, whenever Zitadel sends roles.

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
		$claims[] = ['key' => 'username', 'value' => $username];
	}
}

// groups
$groups = [];
foreach ($userinfo as $claim => $roles) {
	$isRolesClaim = $claim === 'urn:zitadel:iam:org:project:roles'
		|| preg_match('/^urn:zitadel:iam:org:project:\d+:roles$/', $claim);
	if ($isRolesClaim && is_array($roles)) {
		foreach (array_keys($roles) as $role) {
			// PHP turns numeric keys into ints; role keys are strings.
			$groups[(string) $role] = true;
		}
	}
}
if ($groups) {
	$names = array_map('strval', array_keys($groups));
	sort($names, SORT_STRING);
	$claims[] = ['key' => 'groups', 'value' => $names];
}

header('Content-Type: application/json');
echo $claims ? json_encode(['append_claims' => $claims]) : '{}';
