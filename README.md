# scorexl-infra

Single consolidated infra repo for ScoreXL: one `docker-compose.yml`, one
shared Docker network, one nginx config directory, and deploy/bootstrap
scripts — for every sport's API and the shared user-api and web frontend.

This repo **replaces** six previously separate infra repos:

- `scorexl-football-infra`
- `scorexl-basketball-infra`
- `scorexl-nba-infra`
- `scorexl-mlb-infra`
- `scorexl-afl-infra`
- `scorexl-web-infra`

...and adds a seventh sport, **Volleyball**, from day one.

Those six repos are left untouched by this consolidation — they keep
running in production until the manual cutover procedure below is carried
out by a human. This repo does not delete or modify them. **As of
2026-07-23 this repo is the single build source going forward — the six
legacy repos are deprecated and no longer actively updated.**

## Why one repo

The legacy repos each ran their own isolated Docker network, their own
`docker-compose.yml`, and their own nginx site file — despite all sitting on
the *same* droplet (every nginx config does `proxy_pass
http://127.0.0.1:<port>`, which only works same-host). That per-repo
isolation bought nothing and cost real inconsistency:

- Postgres user was `scorexl` in some repos, `postgres` in others.
- Only some repos pinned an explicit `ipam.subnet`.
- Football configured engine URLs via `.env`; basketball and nba hardcoded
  them directly in `docker-compose.yml`.
- **A real bug**: `scorexl-football-infra` and `scorexl-web-infra` both
  bootstrapped nginx to the same file, `/etc/nginx/sites-available/default`
  — whichever was (re-)bootstrapped last silently clobbered the other's
  site config.

This repo fixes all of the above and puts every sport's containers on one
shared network (`scorexl-network`) so they can reach each other by service
name instead of `host.docker.internal` hacks.

**What is deliberately *not* consolidated: the databases.** Each sport (plus
web/user-api) keeps its own isolated Postgres container and its own volume.
Merging live production databases into one instance is a much riskier
migration (pg_dump/restore, schema collisions) for limited benefit, and
per-sport DB isolation is good practice on its own — a bad migration or
runaway query in one sport's schema can't touch another sport's data.

**Market engines are not separate containers.** As of 2026-07-23, every
sport's market-calculation engines (handicap, over/under, spread, totals,
etc.) were merged into that sport's own API as in-process code — eliminating
the per-engine JVM overhead and the internal HTTP hop. `scorexl-football-
live-opportunities-engine` was kept separate for the same stateful reasons,
but the feature it backed was discontinued 2026-08-08 and its container
dropped from docker-compose — the standalone repo itself is untouched.

## Structure

```
scorexl-infra/
  docker-compose.yml   # shared network + all postgres + all api services
  .env.example          # reconciled superset of all legacy .env.example files
  docker/postgres/      # init.sql per sport
  nginx/
    api.scorexl.com.conf              # football api
    basketball-api.scorexl.com.conf
    nba-api.scorexl.com.conf
    volleyball-api.scorexl.com.conf
    mlb-api.scorexl.com.conf
    afl-api.scorexl.com.conf
    scorexl.com.conf                  # web — distinct filename, fixes the "default" collision bug
    analytics.scorexl.com.conf        # self-hosted Umami dashboard
  scripts/
    bootstrap.sh    # installs docker/nginx, symlinks nginx/*.conf into sites-available + sites-enabled
    deploy.sh        # docker compose pull && up -d, whole stack or one sport via --profile/arg
    dev.sh           # local dev: build from sibling source checkouts instead of pulling GHCR images
```

## Services / ports

| Sport      | Service                                    | Host port(s) |
|------------|---------------------------------------------|--------------|
| Football   | `scorexl-football-api`                      | 4000         |
| Football   | `scorexl-football-postgres`                 | 5432         |
| Basketball | `scorexl-basketball-api`                    | 5000         |
| Basketball | `scorexl-basketball-postgres`               | 5433         |
| NBA        | `scorexl-nba-api`                           | 7000         |
| NBA        | `scorexl-nba-postgres`                      | 5435         |
| Volleyball | `scorexl-volleyball-api`                    | 8000         |
| Volleyball | `scorexl-volleyball-postgres`               | 5434         |
| MLB        | `scorexl-mlb-api`                           | 10000        |
| MLB        | `scorexl-mlb-postgres`                      | 5437         |
| AFL        | `scorexl-afl-api`                           | 11000        |
| AFL        | `scorexl-afl-postgres`                      | 5438         |
| NFL        | `scorexl-nfl-api`                           | 12000        |
| NFL        | `scorexl-nfl-postgres`                      | 5439         |
| NHL        | `scorexl-nhl-api`                           | 13000        |
| NHL        | `scorexl-nhl-postgres`                      | 5440         |
| Rugby      | `scorexl-rugby-api`                         | 14000        |
| Rugby      | `scorexl-rugby-postgres`                    | 5441         |
| Handball   | `scorexl-handball-api`                      | 15000        |
| Handball   | `scorexl-handball-postgres`                 | 5442         |
| Web        | `scorexl-web`                               | 3000         |
| Web        | `scorexl-user-api`                          | 9000         |
| Web        | `scorexl-user-postgres`                     | 5436         |

All per-sport port numbers are kept identical to the legacy repos on
purpose — nothing calling these ports today (nginx configs, any hardcoded
client URLs) needs to change.

`docker-compose.yml` uses [Compose
profiles](https://docs.docker.com/compose/how-tos/profiles/) — `football`,
`basketball`, `nba`, `volleyball`, `mlb`, `afl` — so `scripts/deploy.sh` can
pull/up one sport at a time. `scorexl-web` / `scorexl-user-api` /
`scorexl-user-postgres` have no profile and are always included, since
user-api is a shared dependency of every sport's API (`USER_API_URL`).

## Migration / cutover procedure (manual — do not automate this)

Every production-affecting step below is meant to be run **by hand, by a
human**, the same way deploys and DDL already work in this project. Nothing
here is wired into CI/CD, and it shouldn't be.

Because this repo intentionally reuses the legacy repos' exact container
names and host ports (see above), a given sport's *new* container cannot run
side-by-side with that same sport's *old* container on this host at the same
time — they'd collide on both the container name and the port binding. So
"stand it up alongside the old stack" means **sport by sport**, not a single
big-bang swap of all six blocks at once:

1. **Prep**: copy `.env.example` to `.env` on the droplet and fill in real
   values. `INTERNAL_API_KEY`, `GH_PACKAGES_TOKEN`, and the api-sports.io
   keys can reuse whatever's already confirmed working. Every sport's
   Postgres password — `FOOTBALL_POSTGRES_PASSWORD`,
   `BASKETBALL_POSTGRES_PASSWORD`, `NBA_POSTGRES_PASSWORD`,
   `MLB_POSTGRES_PASSWORD`, `AFL_POSTGRES_PASSWORD`,
   `USER_POSTGRES_PASSWORD` — **must be copied from the legacy repos'
   real (not `.example`) `.env` files on the droplet before those repos are
   deleted**, not invented, or the new containers won't be able to
   authenticate against the existing data. Don't assume a sport has "no
   legacy data to match" just because it's a recent pilot (Volleyball,
   MLB, AFL) — check `docker volume ls | grep postgres` first; if a
   `scorexl-<sport>-infra_...` volume already exists, that sport has real
   data and needs its real password, the same as football/basketball/nba.
   Discovered the hard way 2026-07-23: guessed fresh passwords for
   MLB/AFL/Volleyball assuming no prior deploy, which caused an hours-long
   Hibernate dialect-resolution crash loop (`Unable to determine Dialect
   without JDBC metadata` — the real symptom of a failed DB login, not an
   actual dialect problem) that pegged CPU on every restart. MLB/AFL turned
   out to already use the account-wide `scorexl`/`scorexl` credential;
   Volleyball's real password was lost when its legacy repo/`.env` were
   deleted before being copied out, so its volume was abandoned and
   recreated fresh (`external:`/`name:` removed from its entry in
   `docker-compose.yml`'s `volumes:` block) — acceptable since it was a
   brand-new pilot with negligible data, but **copy every password out
   before deleting a legacy repo**, not after.
   **Also verify the actual DB name and username against a working DBeaver
   connection (or equivalent) before assuming they match this repo's
   defaults** — confirmed 2026-07-23 that football's real DB is named
   `scorexl` (not `scorexl_football`, a holdover from when football was the
   only sport) and `scorexl-user-api`'s real user is `postgres` (not
   `scorexl` like every other sport) — both now hardcoded to match reality
   in `docker-compose.yml`, but don't assume the legacy `.env.example` files
   in those repos are accurate; they weren't. **The Postgres volumes must
   also be pointed at the legacy repos' real volumes** — see the
   `external: true` / `name:` overrides in this repo's `docker-compose.yml`'s
   `volumes:` block (all except Volleyball's, now fresh); Compose prefixes
   unnamed volumes with the project directory name, so a fresh
   `scorexl-infra` checkout creates brand-new empty volumes instead of
   reusing `scorexl-<sport>-infra`'s unless told not to.
2. **Pick one sport to cut over first** (e.g. football). Confirm nothing
   else currently depends on `scorexl-football-infra`'s specific container
   staying up mid-swap (it doesn't — every sport's API is independent).
3. Stop *only that sport's* containers in the legacy repo:
   `docker compose stop` (or `down`) inside `scorexl-football-infra`. This
   frees the container name and host ports.
4. From this repo, bring up just that sport:
   `./scripts/deploy.sh football` (equivalent to
   `docker compose --profile football up -d`, plus `scorexl-web` /
   `scorexl-user-api`, which are always-on).
5. **Verify** the sport's API responds correctly through the *new* stack —
   at minimum a real endpoint through `curl http://127.0.0.1:<port>/...`,
   and check `docker logs scorexl-<sport>-api` for startup errors, before
   touching anything else.
6. Repeat steps 2–5 for basketball, nba, volleyball, mlb, afl, and
   web/user-api, one at a time. Volleyball/MLB/AFL have no legacy stack to
   cut over from — their containers just start fresh from this repo.
7. **Only after every sport's API has been verified working through this
   repo's stack**, run `./scripts/bootstrap.sh` to point nginx at this
   repo's `nginx/*.conf` files instead of the legacy repos'. Confirm
   `scorexl.com` and every `*-api.scorexl.com` subdomain resolve correctly
   afterward.
8. **Decommission** the legacy repos only after nginx + all containers are
   confirmed serving from this repo: remove their `docker compose` stacks
   (`docker compose down`, optionally `-v` if you're also ready to delete
   their now-unused Postgres volumes — those hold the same data this repo's
   equivalent Postgres containers took over, so only do this once you're
   confident nothing needs to roll back), and archive/delete the legacy
   GitHub repos.

If anything looks wrong at any verification step, the rollback is simple:
stop this repo's container for that sport, restart the legacy repo's
container (it's still there, just stopped, with its data volume intact),
and investigate before trying again. Nothing is destructive until step 8.
