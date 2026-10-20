<?php
// Zitadel Actions v2 target for the function preuserinfo (see README.md next to this file).
// Adds a "username" claim with the plain username (preferred_username stays username@orgdomain).
// Only when the "profile" scope was requested: Zitadel sends no scopes to actions, but it only puts
// preferred_username into the userinfo when profile was requested.

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
header('Content-Type: application/json');
if (empty($req['userinfo']['preferred_username'])) {
	echo '{}'; // profile scope not requested
	exit;
}

$username = $req['user']['username'] ?? '';
$domain = $req['org']['primary_domain'] ?? '';

// The username normally has no domain; strip "@<org primary domain>" in case it was created with one.
if ($domain !== '' && str_ends_with(strtolower($username), '@' . strtolower($domain))) {
	$username = substr($username, 0, -strlen($domain) - 1);
}

if ($username === '') {
	echo '{}';
	exit;
}
echo json_encode([
	'append_claims' => [
		['key' => 'username', 'value' => $username],
	],
]);
