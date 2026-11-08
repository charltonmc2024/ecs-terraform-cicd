# ecs-mongodb-api - read-only MongoDB demo API

A small, standalone FastAPI service that exposes **read-only** views of the
synthetic dataset in MongoDB Atlas. It is separate from the Next.js landing page
(`ecs-application/`) and from the team repositories. It performs **no writes**.

## Endpoints

- `GET /health` - liveness, unauthenticated, does not touch MongoDB.
- `GET /ready` - readiness (DB ping). **Requires** `x-api-key`.
- `GET /schools` - admin_staff_mongodb.school_collection. Requires `x-api-key`.
- `GET /users?role=teacher|student` - teacher_student_db.user_collection. Requires `x-api-key`.
- `GET /classes` - teacher_student_db.class_collection. Requires `x-api-key`.
- `GET /assignments` - teacher_student_db.assignments_collection. Requires `x-api-key`.

All list endpoints accept `limit` (1-100, default 20) and `offset` (>=0), sort
deterministically by `_id`, and return:

    { "data": [ ... ],
      "pagination": {"limit","offset","count","total"},
      "meta": {"database","collection"} }

## Security

- API-key boundary (`x-api-key`); CORS is an allowlist and is **not** authentication.
- Responses use explicit field allowlists; `email`, `password`, `auth0_user_id`,
  `auth_provider`, `profile_picture`, `subscriber_id` are never returned (including
  nested teacher/student objects). Assignment `questions` are omitted.
- All DB access is read-only; a static test forbids any write API in `app/`.
- Use a **read-only** Atlas user for `MONGODB_URI` (never the readWrite import user).
- Credentials come from the environment (Secrets Manager in ECS); none in source.
- Logs redact any mongodb URI and the API key; errors are generic.

## Local development (offline-friendly)

Create the venv and install dev deps:

    cd ecs-mongodb-api
    python3 -m venv .venv
    . .venv/bin/activate
    pip install -r requirements-dev.txt

Run the offline test suite (no Atlas connection; fake in-memory DB):

    pytest -q

To run locally against a real READ-ONLY Atlas user, set MONGODB_URI and API_KEY
in your environment (never commit them) and start the ASGI server
(`app.main:app`) with uvicorn. `.venv/` and `.env` are gitignored and excluded
from the Docker build context.

## Docker

Build the image and run it, providing MONGODB_URI, API_KEY, and
CORS_ALLOW_ORIGINS as runtime environment variables. The image runs as a
non-root user and contains no secrets.

## Routing prefix (API_PREFIX)

`API_PREFIX` controls where every route except `/health` is mounted.

| `API_PREFIX` | `/health` | `/ready` and data routes |
|---|---|---|
| empty (default, local Docker) | `/health` | `/ready`, `/schools`, `/users`, `/classes`, `/assignments` |
| `/v1` (planned ECS value) | `/health` | `/v1/ready`, `/v1/schools`, `/v1/users`, `/v1/classes`, `/v1/assignments` |

- `/health` is never prefixed. The ALB health check uses it and CloudFront does not
  route it to the API.
- When a prefix is set, the unprefixed data and readiness routes are not served (404).
- When a prefix is set, trailing-slash redirects are disabled: `/v1/schools/` returns 404.
  Behind CloudFront the origin sees the internal ALB host name, so a redirect could point
  browsers at it. With no prefix, the default FastAPI redirect behavior is unchanged.
- The value must start with `/`; each segment may contain letters, digits, `.`, `_`, `~`
  and `-`, and must start with a letter or digit (maximum 64 characters). One trailing
  slash is removed. Anything else (no leading slash, `//`, `..`, spaces, `?`, `#`,
  percent-encoding) stops the app at startup with `API_PREFIX is invalid`.
- `root_path` is not used. It is meant for proxies that strip a prefix, and CloudFront
  does not.
- `/docs`, `/redoc` and `/openapi.json` behave as before (unprefixed, not API-key
  protected). They are not routed by CloudFront's `/v1/*` behavior.

### ECS (future)

Set `API_PREFIX` as a plain `environment` entry in the task definition (it is not a
secret). Credentials stay in `secrets`, pointing at Secrets Manager ARNs, and must be
mapped to the names this app reads: `MONGODB_URI` for the read-only Atlas URI and
`API_KEY` for the key. Note that the existing Next.js task injects `MONGODB_URL`, which
this app does not read. Use one Terraform variable for both the ALB listener rule pattern
(`<prefix>/*`) and the container `API_PREFIX` so they cannot drift.

### Tests and the environment

The offline tests expect `API_PREFIX` to be unset in your shell. Default-mode tests build
the app from the current environment, so an exported `API_PREFIX` makes them fail by
design. `tests/test_prefix.py` sets and clears the variable itself and clears
`MONGODB_URI` so no database client is ever opened.

## Scope / boundaries

Everything lives under `ecs-mongodb-api/`. This app does not modify the Next.js
app, the Terraform project, the synthetic dataset/importer, or any team repo, and
it does not deploy anything.
