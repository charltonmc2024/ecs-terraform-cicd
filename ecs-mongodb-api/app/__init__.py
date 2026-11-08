"""Read-only FastAPI demo over the synthetic MongoDB Atlas dataset.

No writes, ever. Credentials come from the environment (Secrets Manager in ECS);
nothing secret is stored in source. Responses use explicit field allowlists and
never include email/password/auth0 identifiers.
"""
