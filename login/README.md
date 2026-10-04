# Zitadel login with the LeiCraft_MC theme

The login in the bundle image is the upstream Zitadel login (`apps/login` of
[zitadel/zitadel](https://github.com/zitadel/zitadel)), built from source at `ZITADEL_VERSION` in
the `login` stage of the [Dockerfile](../docker/Dockerfile). Nothing is forked; the only `.tsx`
file touched is `theme-wrapper.tsx` — one added line for font weights (table below). The stage
checks out the upstream tag, copies [overrides/](overrides/) over it and builds
it like upstream does. Every login flow, security fix and translation comes unchanged from upstream.

It takes the same environment variables as `ghcr.io/zitadel/zitadel-login`, each prefixed with
`LCMC_AUTH_LOGIN_` (for example `LCMC_AUTH_LOGIN_AUDIENCE`). In the bundle it listens on port 12192
under `/ui/v2/login` (see the [README](../README.md)).

## What is replaced

`overrides/` mirrors the upstream repository. Changes inside upstream files are marked `LCMC:`.

| File | Kind | What it does |
| --- | --- | --- |
| `apps/login/.env.production.local` | added | Selects the theme at build time: `NEXT_PUBLIC_THEME_APPEARANCE=lcmc`, roundness, layout, spacing. |
| `apps/login/src/lib/theme.ts` | replaced | Adds the `lcmc` appearance preset. It only adds marker classes (`lcmc-card`, `lcmc-surface`, `lcmc-button`, `lcmc-idp-button`) to the card, switches, buttons and IdP buttons. |
| `apps/login/src/components/theme-wrapper.tsx` | replaced | One `LCMC:` line: the injected `@font-face` for the branding font declares `font-weight: 100 900`, so a uploaded **variable** font renders the medium (500) and semibold (600) the theme builds on. Without it the face registers at 400 only and 500/600 silently fall back to the built-in Lato's weights. |
| `apps/login/src/styles/globals.scss` | replaced | Loads `_lcmc.scss` at the end. |
| `apps/login/src/styles/_lcmc.scss` | added | The theme: NuxtUI v4 recipes (checked against the `@nuxt/ui` v4.9 sources) for buttons, inputs, form fields, the card, checkbox, alert, IdP buttons, account rows and the account pill, avatars, radio tiles and the dropdown. |

`_lcmc.scss` sits outside every CSS `@layer`, so it wins over Tailwind's utility classes without
`!important`. Apart from the amber of warning alerts it never uses fixed colors. Every color comes
from the branding (label policy) variables the login sets per instance and organization
(`--theme-{light|dark}-{primary|background|warn|text}-*`).

## Branding per instance or organization

Colors, logo, font and theme mode stay in the Zitadel branding settings, per instance and per
organization. For the LeiCraft_MC look, set the instance default branding to the LeiCraft_MC colors
and upload Rubik as the font. Organizations can still override everything. Pages that don't know
the user's organization yet (for example `/idp` or `/mfa` opened without a login name) show the
**instance** branding, so set logo, font and colors there too, not only on the organization.
That is upstream behavior, the default login does the same. `/idp` lists the instance's identity
providers the same way, so add the IdPs there too. Branding changes only show after they are
applied ("Apply" in the console); Zitadel serves the active branding, not the preview.

How the theme uses the branding colors:

| Branding color | Where it shows |
| --- | --- |
| Background | The card, exactly as configured (like upstream). The page behind it is the same color mixed toward black; inputs, buttons, rows and borders are steps from it toward the font color. |
| Font | Titles, names and input text exactly; body text, labels and secondary text are the font color mixed toward the background. |
| Primary | Primary buttons, links, focus rings, selected tiles. Text on primary buttons is upstream's computed contrast color. |
| Warn | Errors, the end-session badge, destructive buttons. |

The steps are calibrated on NuxtUI's slate palette: a dark background of slate-900 (`#0f172b`)
with white text gives exactly the LeiCraft_MC app look (slate-900 card on a slate-950 page,
slate-800/700 controls). A slate-950 background (`#020618`) gives a slate-950 card on a near-black
page.

**Font:** upload a **variable** font file — the Rubik VF (one file covering weights 300–900), not a
static `Rubik-Regular.ttf`. Zitadel stores a single font file, and the LeiCraft_MC look needs real
500 (buttons, labels) and 600 (headings) weights: only a variable font carries them in one file, and
the overridden `theme-wrapper.tsx` declares the `100 900` weight range for exactly that case. A
static upload still works, but everything renders at its single baked weight. If the font does not
apply at all, check in the browser DevTools that the branding request's `fontUrl` is set and the
font file loads (same origin, see the routing section of the main README) — a font configured on one
instance does not apply to another instance's or org's login.

Theme files can't change markup. Anything that needs new elements or a different structure isn't
possible here, for example a footer with imprint and privacy links. Upstream only shows terms of
service and privacy links on the register page.

## Changing the theme

Edit `overrides/apps/login/src/styles/_lcmc.scss` and rebuild. It keys on the marker classes above
and, where there is no marker, on upstream's own classes and `data-testid`s (for example
`input.bg-input-light-background` or `button[data-testid="register-button"]`). Because those rules
outrank all utilities, upstream's `hover:`, `focus:`, `disabled:` and `dark:` classes no longer
apply to any property set there, so write every state out.

`NEXT_PUBLIC_*` values are compiled into the build. Setting them on the container has no effect.

## Upgrading Zitadel

1. Set `ARG ZITADEL_VERSION` in the [Dockerfile](../docker/Dockerfile) to the new tag and build. Zitadel
   and the login both use it.
2. If upstream changed a file that is replaced, `apply-overrides.sh` fails the build and names the
   file. The same happens if upstream added a file with the same name as one of ours. Then:
   - look at the upstream change, for example
     `https://github.com/zitadel/zitadel/compare/<old tag>...<new tag>`, filtered to the file;
   - take the new upstream file, re-apply the `LCMC:` changes and save it under `overrides/`;
   - record the new checksums: `login/upstream-checksums.sh <new tag>`.

   [upstream.sha256](upstream.sha256) also pins upstream's `apps/login/Dockerfile`. If it changes,
   carry over changes to its environment and start command into
   [docker/scripts/run-login.sh ](../docker/scripts/run-login.sh ). The login runs on Bun there, so upstream's
   Node version doesn't apply.
3. Compare screenshots of the main pages: login name, password, MFA, register, account
   selection, in light and dark. A renamed upstream class doesn't fail the build. The rule that
   used it just stops applying.
