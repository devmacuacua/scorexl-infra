# scorexl-infra

Single consolidated infra repo for ScoreXL: one `docker-compose.yml`, one
shared Docker network, one nginx config directory, and deploy/bootstrap
scripts — for every sport's API + engines, the shared user-api, and the web
frontend.

This repo **replaces** four previously separate infra repos:

- `scorexl-football-infra`
- `scorexl-basketball-infra`
- `scorexl-nba-infra`
- `scorexl-web-infra`

...and adds a fifth sport, **Volleyball**, from day one.

Those four repos are left untouched by this consolidation — they keep
running in production until the manual cutover procedure below is carried
out by a human. This repo does not delete or modify them.

## Why one repo

The four legacy repos each ran their own isolated Docker network, their own
`docker-compose.yml`, and their own nginx site file — despite all sitting on
the *same* droplet (every nginx config does `proxy_pass
http://127.0.0.1:<port>`, which only works same-host). That per-repo
isolation bought nothing and cost real inconsistency:

- Postgres user was `scorexl` in some repos, `postgres` in others.
- Only two of the four repos pinned an explicit `ipam.subnet`.
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
Merging 4+ live production databases into one instance is a much riskier
migration (pg_dump/restore, schema collisions) for limited benefit, and
per-sport DB isolation is good practice on its own — a bad migration or
runaway query in one sport's schema can't touch another sport's data.

## Structure

```
scorexl-infra/
  docker-compose.yml   # shared network + all postgres + all api/engine services
  .env.example          # reconciled superset of all 4 legacy .env.example files + volleyball
  docker/postgres/      # init.sql per sport (only football's does anything: it also
                         # creates scorexl_football_live for the live-opportunities engine)
  nginx/
    api.scorexl.com.conf              # football api
    basketball-api.scorexl.com.conf
    nba-api.scorexl.com.conf
    volleyball-api.scorexl.com.conf   # new
    scorexl.com.conf                  # web — distinct filename, fixes the "default" collision bug
  scripts/
    bootstrap.sh    # installs docker/nginx, symlinks nginx/*.conf into sites-available + sites-enabled
    deploy.sh        # docker compose pull && up -d, whole stack or one sport via --profile/arg
```

## Services / ports

| Sport      | Service                                  | Host port(s)     |
|------------|-------------------------------------------|-------------------|
| Football   | `scorexl-football-api`                    | 4000              |
| Football   | `scorexl-football-*-engine` (11 engines)  | 4001–4011         |
| Football   | `scorexl-football-postgres`               | 5432              |
| Basketball | `scorexl-basketball-api`                  | 5000              |
| Basketball | `scorexl-basketball-*-engine` (10 engines)| 5001–5010         |
| Basketball | `scorexl-basketball-postgres`             | 5433              |
| NBA        | `scorexl-nba-api`                         | 7000              |
| NBA        | `scorexl-nba-*-engine` (12 engines)       | 7001–7012         |
| NBA        | `scorexl-nba-postgres`                    | 5435              |
| Volleyball | `scorexl-volleyball-api` (new)             | 8000              |
| Volleyball | `scorexl-volleyball-winner-engine` (new)   | 8001              |
| Volleyball | `scorexl-volleyball-postgres` (new)         | 5434 *(previously skipped by the 4 legacy repos)* |
| Web        | `scorexl-web`                              | 3000              |
| Web        | `scorexl-user-api`                         | 9000              |
| Web        | `scorexl-user-postgres`                    | 5436              |

All per-sport port numbers are kept identical to the legacy repos on
purpose — nothing calling these ports today (nginx configs, any hardcoded
client URLs) needs to change.

`docker-compose.yml` uses [Compose
profiles](https://docs.docker.com/compose/how-tos/profiles/) — `football`,
`basketball`, `nba`, `volleyball` — so `scripts/deploy.sh` can pull/up one
sport at a time. `scorexl-web` / `scorexl-user-api` / `scorexl-user-postgres`
have no profile and are always included, since user-api is a shared
dependency of every sport's API (`USER_API_URL`).

## Migration / cutover procedure (manual — do not automate this)

Every production-affecting step below is meant to be run **by hand, by a
human**, the same way deploys and DDL already work in this project. Nothing
here is wired into CI/CD, and it shouldn't be.

Because this repo intentionally reuses the legacy repos' exact container
names and host ports (see above), a given sport's *new* container cannot run
side-by-side with that same sport's *old* container on this host at the same
time — they'd collide on both the container name and the port binding. So
"stand it up alongside the old stack" means **sport by sport**, not a single
big-bang swap of all five blocks at once:

1. **Prep**: copy `.env.example` to `.env` on the droplet and fill in real
   values (reuse the existing secrets from the legacy repos' `.env` files —
   passwords, API keys, `INTERNAL_API_KEY`, etc. Postgres user is now
   `scorexl` everywhere regardless of what the legacy repo used).
2. **Pick one sport to cut over first** (e.g. football). Confirm nothing
   else currently depends on `scorexl-football-infra`'s specific container
   staying up mid-swap (it doesn't — every sport's API is independent).
3. Stop *only that sport's* containers in the legacy repo:
   `docker compose stop` (or `down`) inside `scorexl-football-infra`. This
   frees the container name and host ports 4000–4011/5432.
4. From this repo, bring up just that sport:
   `./scripts/deploy.sh football` (equivalent to
   `docker compose --profile football up -d`, plus `scorexl-web` /
   `scorexl-user-api`, which are always-on).
5. **Verify** the sport's API responds correctly through the *new* stack —
   at minimum `curl http://127.0.0.1:4000/actuator/health` (or whatever
   health/status endpoint the API exposes) and a couple of real endpoints,
   before touching anything else. Check `docker logs scorexl-football-api`
   and its engines for startup errors.
6. Repeat steps 2–5 for basketball, nba, and web/user-api, one at a time.
   Volleyball has no legacy stack to cut over from — its containers just
   start fresh from this repo once its two images (`scorexl-volleyball-api`,
   `scorexl-volleyball-winner-engine`) exist on `ghcr.io`.
7. **Only after every sport's API has been verified working through this
   repo's stack**, run `./scripts/bootstrap.sh` to point nginx at this
   repo's `nginx/*.conf` files instead of the legacy repos'. Confirm
   `scorexl.com` and `api.scorexl.com` both resolve correctly afterward —
   this is the concrete proof that the old "both bootstrap to
   `sites-available/default`" collision bug is actually fixed, since they
   now live at distinct filenames (`scorexl.com.conf`,
   `api.scorexl.com.conf`) and neither one overwrites the other.
8. **Decommission** the four legacy repos only after nginx + all containers
   are confirmed serving from this repo: remove their `docker compose`
   stacks (`docker compose down`, optionally `-v` if you're also ready to
   delete their now-unused Postgres volumes — those hold the same data this
   repo's equivalent Postgres containers took over, so only do this once
   you're confident nothing needs to roll back), and archive/delete the
   four GitHub repos.

If anything looks wrong at any verification step, the rollback is simple:
stop this repo's container for that sport, restart the legacy repo's
container (it's still there, just stopped, with its data volume intact),
and investigate before trying again. Nothing is destructive until step 8.

## Volleyball

`scorexl-volleyball-api` and `scorexl-volleyball-winner-engine` are being
built in parallel repos and don't have published images yet — the service
blocks here are ready to go the moment `ghcr.io/devmacuacua/scorexl-
volleyball-api:latest` and `ghcr.io/devmacuacua/scorexl-volleyball-winner-
engine:latest` exist. Until then, `docker compose pull` for the
`volleyball` profile will simply fail with an image-not-found error — this
is expected, not a bug in this repo.

Volleyball reuses the **same api-sports.io account key** as every other
sport (`API_VOLLEYBALL_API_KEY` can be set to the same value as
`API_FOOTBALL_API_KEY` / `API_BASKETBALL_KEY` / `API_NBA_KEY`) — confirmed
live against the account that one key works across every api-sports.io
product on it, so this doesn't need a separately-issued key.
