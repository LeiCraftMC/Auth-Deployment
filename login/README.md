# Zitadel login with the LeiCraft_MC theme

The login in the bundle image is the upstream Zitadel login (`apps/login` of
[zitadel/zitadel](https://github.com/zitadel/zitadel)), built from source at `ZITADEL_VERSION` in
the `login` stage of the [Dockerfile](../Dockerfile). Nothing is forked and no `.tsx` file is
changed. The stage checks out the upstream tag, copies [overrides/](overrides/) over it and builds
it like upstream does. Every login flow, security fix and translation comes unchanged from upstream.

It takes the same environment variables as `ghcr.io/zitadel/zitadel-login`. In the bundle it listens
on port 12192 under `/ui/v2/login` (see the [README](../README.md)).

## What is replaced

`overrides/` mirrors the upstream repository. Changes inside upstream files are marked `LCMC:`.

| File | Kind | What it does |
| --- | --- | --- |
| `apps/login/.env.production.local` | added | Selects the theme at build time: `NEXT_PUBLIC_THEME_APPEARANCE=lcmc`, roundness, layout, spacing. |
| `apps/login/src/lib/theme.ts` | replaced | Adds the `lcmc` appearance preset. It only adds marker classes (`lcmc-card`, `lcmc-surface`, `lcmc-button`, `lcmc-idp-button`) to the card, switches, buttons and IdP buttons. |
| `apps/login/src/styles/globals.scss` | replaced | Loads `_lcmc.scss` at the end. |
| `apps/login/src/styles/_lcmc.scss` | added | The theme: NuxtUI v4 recipes for buttons, inputs, form fields and the card, sized like the Login-UI port. |

`_lcmc.scss` sits outside every CSS `@layer`, so it wins over Tailwind's utility classes without
`!important`. It never uses fixed colors. Every color comes from the branding (label policy)
variables the login sets per instance and organization (`--theme-{light|dark}-{primary|background|warn|text}-*`).

## Branding per instance or organization

Colors, logo, font and theme mode stay in the Zitadel branding settings, per instance and per
organization. For the LeiCraft_MC look, set the instance default branding to the LeiCraft_MC colors
and upload Rubik as the font. Organizations can still override everything.

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

1. Set `ARG ZITADEL_VERSION` in the [Dockerfile](../Dockerfile) to the new tag and build. Zitadel
   and the login both use it.
2. If upstream changed a file that is replaced, `apply-overrides.sh` fails the build and names the
   file. The same happens if upstream added a file with the same name as one of ours. Then:
   - look at the upstream change, for example
     `https://github.com/zitadel/zitadel/compare/<old tag>...<new tag>`, filtered to the file;
   - take the new upstream file, re-apply the `LCMC:` changes and save it under `overrides/`;
   - record the new checksums: `login/upstream-checksums.sh <new tag>`.

   [upstream.sha256](upstream.sha256) also pins upstream's `apps/login/Dockerfile`. If it changes,
   carry over changes to its environment and start command into `run_login` in
   [docker/entrypoint.sh](../docker/entrypoint.sh). The login runs on Bun there, so upstream's
   Node version doesn't apply.
3. Compare screenshots of the main pages: login name, password, MFA, register, account
   selection, in light and dark. A renamed upstream class doesn't fail the build. The rule that
   used it just stops applying.
