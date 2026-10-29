locals {
  # Single naming base for every resource name in this module.
  name_prefix = "${var.app_name}-${var.environment}"

  # Secrets are wired only when a secret ARN is supplied. In DEV the default is null,
  # so this evaluates to an empty list and the task definition contains no secret
  # references — zero secret wiring appears in the plan (R7). When an ARN is provided,
  # the MongoDB Atlas connection URI is injected as the MONGODB_URL environment secret
  # from that ARN, which is exactly the variable the application reads at startup.
  container_secrets = concat(
    var.app_secret_arn == null ? [] : [
      {
        name      = "MONGODB_URL"
        valueFrom = var.app_secret_arn
      }
    ],
    var.staff_admin_secret_arn == null ? [] : [
      {
        name      = "STAFF_ADMIN_MONGO_URL"
        valueFrom = var.staff_admin_secret_arn
      }
    ]
  )

  # Scoped read policy for the single supplied secret ARN. Gated on var.app_secret_arn:
  # with the DEV default (null) this document is not created at all, so no secret-read
  # permission appears in the plan. The resource is EXACTLY var.app_secret_arn — never a
  # wildcard — so the execution role can read only this one secret. ssm:GetParameters is
  # included so the same wiring works whether the ARN points at Secrets Manager or an SSM
  # Parameter Store parameter; both actions are still scoped to the single ARN.
  mongo_secret_arns = distinct(compact([
    var.app_secret_arn,
    var.staff_admin_secret_arn
  ]))
}
