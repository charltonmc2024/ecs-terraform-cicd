# Requirements Document

## Introduction

This spec covers a new reusable Terraform observability module for the Erudition Solution development
environment. The `Observability_Module` is a cross-cutting monitoring module at
`ecs-terraform/modules/observability/`, consumed by the Terraform root module at
`ecs-terraform/envs/dev/`. It provides monitoring and alerting over the already-deployed development
architecture: the ECS Fargate service and internal Application Load Balancer owned by the backend module,
the CloudFront distribution owned by the edge module, and the external MongoDB Atlas M0 database reached by
the ECS tasks over NAT egress.

The platform is an adaptive educational assessment application for school districts. Students sign in and
take timed, adaptive practice assessments and submit answers, while teachers review student progress and
class-level results. The application is served from the internet through CloudFront, forwards `/api/*` to
the internal ALB through a CloudFront VPC Origin, and runs the API on ECS Fargate in private subnets.
Because students interact with the API live during an assessment, visibility into API availability (ALB
healthy hosts), server errors (ALB 5xx), and compute saturation (ECS CPU and memory) directly protects the
student experience: an unhealthy service, a spike in 5xx responses, or an exhausted task can interrupt a
student mid-assessment or silently lose a submitted answer. Each observability resource in this spec exists
to give operators that visibility and to notify them when the service degrades.

This module is purely observational. It CONSUMES resource identifiers from the network, backend, and edge
modules and MUST NOT create, modify, or own any application resource (no ECS, ALB, ECR, S3, CloudFront, VPC,
or security-group resources). Per the project architecture, the observability module "monitors deployed
resources." It MUST NOT be referenced by the network, backend, or edge modules, and MUST NOT introduce a
circular module dependency.

### Resource-ownership and non-duplication facts (established by inspecting the backend module)

Two ownership facts cross the module boundary and are stated up front because they constrain this spec:

- **The ECS application CloudWatch Log Group already exists and is owned by the backend module.** The
  backend module declares `aws_cloudwatch_log_group.app` with name `"${local.name_prefix}-app"` and
  retention from the backend's `var.log_retention_days` (DEV default 14 days). The ECS task definition ships
  container stdout/stderr there via the awslogs driver. The `Observability_Module` MUST NOT create or
  recreate this log group, and MUST NOT declare a second `aws_cloudwatch_log_group` for ECS application
  logs. The ECS application log group and its retention remain owned by the backend module. The
  `Observability_Module` owns alarms, the dashboard, and the optional SNS notification path only.

- **The ECS service already has an autoscaling CPU target-tracking policy owned by the backend module.** The
  backend module declares `aws_appautoscaling_policy.cpu` (an `ECSServiceAverageCPUUtilization`
  target-tracking policy). The CPU and memory alarms in this spec are NOTIFICATION/visibility alarms that are
  distinct from autoscaling: they do not scale the service, do not create or modify any autoscaling policy or
  scalable target, and do not conflict with the existing target-tracking behavior.

### Integration facts and the required additive backend output change

The alarms and dashboard need CloudWatch dimension values. The backend module currently outputs
`ecr_repository_url`, `alb_dns_name`, `alb_arn`, `ecs_cluster_name`, and `ecs_service_name`.

- **ECS dimensions are AVAILABLE.** ECS alarms require `ClusterName` (from `ecs_cluster_name`) and
  `ServiceName` (from `ecs_service_name`), both already output.

- **ALB dimensions are a GAP.** ALB and target-group CloudWatch metrics are dimensioned by the ALB ARN
  *suffix* (`LoadBalancer` = `app/<name>/<id>`) and the target group ARN *suffix* (`TargetGroup` =
  `targetgroup/<name>/<id>`). The backend currently outputs the full `alb_arn` but no ALB ARN suffix and no
  target group ARN or suffix, and no ECS log group name. These dimension values MUST be obtained without
  hardcoding — either by adding minimal, additive backend module outputs (`alb_arn_suffix`,
  `target_group_arn_suffix`, and optionally `ecs_log_group_name`) or by deriving the suffixes from the full
  ARNs. No AWS account IDs, ARNs, resource names, or dimension strings may be hardcoded; every value comes
  from a module output, a variable, or a Terraform reference. This may require an additive interface change
  to the backend module (new outputs only, no behavior change), which is acceptable under the module-boundary
  rules because the consumer needs values the producer should expose.

- **CloudFront metrics are region-scoped.** CloudFront publishes `AWS/CloudFront` metrics only in
  `us-east-1`. If the dashboard includes CloudFront widgets, the design must account for the metric region
  via the appropriate provider/region consideration. CloudFront widgets are OPTIONAL for DEV.

- **MongoDB Atlas emits no AWS metrics.** The application database is MongoDB Atlas M0, an external managed
  service reached over NAT egress. It is not an AWS resource and publishes no CloudWatch metrics, so this
  spec creates no Atlas database alarms or Atlas database widgets.

This spec is DEV only. It MUST NOT create `envs/staging` or `envs/prod` and MUST NOT create staging or
production resources. The module stays environment-independent: typed variables with no DEV literals inside
the module, and DEV values supplied through `envs/dev/terraform.tfvars`. This spec writes no Terraform in the
requirements phase, performs no `terraform apply`, creates no AWS resources, and modifies no state.

## Glossary

- **Observability_Module**: The reusable Terraform module at `ecs-terraform/modules/observability/` that
  owns CloudWatch alarms, the CloudWatch dashboard, and the optional SNS notification path for the
  development environment.
- **Dev_Root**: The Terraform root module and single source of truth for the development environment at
  `ecs-terraform/envs/dev/`, which composes the network, backend, edge, and observability modules.
- **Backend_Module**: The existing module at `ecs-terraform/modules/backend/` that owns the ECS Fargate
  service, the internal ALB and its target group, ECR, the ECS application log group
  (`aws_cloudwatch_log_group.app`), and the ECS autoscaling CPU target-tracking policy. It exposes
  `ecr_repository_url`, `alb_dns_name`, `alb_arn`, `ecs_cluster_name`, and `ecs_service_name`.
- **Edge_Module**: The existing module at `ecs-terraform/modules/edge/` that owns the CloudFront
  distribution.
- **ECS_Service**: The `aws_ecs_service` application workload owned by the Backend_Module, dimensioned in
  CloudWatch by `ClusterName` and `ServiceName`.
- **Internal_ALB**: The internal `aws_lb` owned by the Backend_Module, dimensioned in CloudWatch by the ALB
  ARN suffix (`LoadBalancer`).
- **Target_Group**: The `aws_lb_target_group` owned by the Backend_Module, dimensioned in CloudWatch by the
  target group ARN suffix (`TargetGroup`).
- **ECS_App_Log_Group**: The existing `aws_cloudwatch_log_group.app` owned by the Backend_Module (name
  `"${name_prefix}-app"`), referenced but never recreated by the Observability_Module.
- **CPU_Alarm**: A CloudWatch metric alarm on ECS service CPU utilization used for notification and
  visibility, distinct from the Backend_Module autoscaling policy.
- **Memory_Alarm**: A CloudWatch metric alarm on ECS service memory utilization used for notification and
  visibility.
- **Unhealthy_Host_Alarm**: A CloudWatch metric alarm on the Target_Group `UnHealthyHostCount` metric.
- **Target_5xx_Alarm**: A CloudWatch metric alarm on the ALB `HTTPCode_Target_5XX_Count` metric.
- **ELB_5xx_Alarm**: A CloudWatch metric alarm on the ALB `HTTPCode_ELB_5XX_Count` metric.
- **Latency_Alarm**: A CloudWatch metric alarm on the ALB `TargetResponseTime` metric (seconds), used to notify operators when API response latency is high enough to degrade the student assessment experience.
- **Dashboard**: The single `aws_cloudwatch_dashboard` presenting application and infrastructure metrics.
- **SNS_Topic**: The optional `aws_sns_topic` and its email subscription used as the alarm notification
  target, disabled by default in DEV.
- **Alarm_Actions**: The list of notification targets attached to each CloudWatch alarm; empty when SNS is
  disabled.
- **Name_Prefix**: The derived naming prefix `"${app_name}-${environment}"` used to name observability
  resources consistently.

## Requirements

### Requirement 1: Reusable, environment-independent observability module

**User Story:** As an infrastructure engineer, I want a reusable observability module that is driven entirely by typed inputs, so that the development environment is monitored today and future environments can consume the same module without redesign.

#### Acceptance Criteria

1. THE Observability_Module SHALL be located at `ecs-terraform/modules/observability/`.
2. THE Observability_Module SHALL derive all observability resource names from a `Name_Prefix` local equal to `"${app_name}-${environment}"`, where `app_name` matches the pattern `^[a-z][a-z0-9-]{1,30}[a-z0-9]$` and `environment` is one of `dev`, `staging`, or `prod`.
3. THE Observability_Module SHALL declare every environment-specific value as a typed input variable with an explicit `type` and `description`, and SHALL NOT embed development-specific literal values in the module source.
4. IF a required input variable is supplied without an explicit `type` declaration, THEN THE Observability_Module SHALL fail `terraform validate` with an error indicating the missing type.
5. THE Observability_Module SHALL inherit the default AWS provider from the Dev_Root and SHALL NOT declare a backend block or a `provider` block.
6. WHERE a resource supports tagging, THE Observability_Module SHALL apply the common tag set consisting of exactly the keys `Project`, `Environment`, `ManagedBy`, and `Owner` passed in from the Dev_Root, merged with any resource-specific `Name` tag, such that all four common keys are present on the resource.
7. THE Observability_Module SHALL obtain every AWS account identifier, ARN, VPC ID, subnet ID, security-group ID, ECR URL, CloudFront distribution ID, and CloudWatch dimension string from input variables, module outputs, data sources, or Terraform references, and SHALL NOT contain any such value as a hardcoded literal in the module source.
8. THE Observability_Module SHALL NOT declare an ECS application log group or an ECS autoscaling policy, which are owned by the backend module.

### Requirement 2: Observational-only boundary and dependency direction

**User Story:** As an architect, I want the observability module to only observe deployed resources, so that the established `network → backend → edge` dependency direction is preserved and no circular dependency is introduced.

#### Acceptance Criteria

1. THE Observability_Module SHALL define zero Terraform resources that create or manage ECS clusters, ECS services, ECS task definitions, ALBs, ALB listeners, target groups, ECR repositories, S3 buckets, CloudFront distributions, VPCs, subnets, route tables, NAT gateways, internet gateways, VPC endpoints, or security groups.
2. WHEN the Observability_Module requires a network, backend, or edge resource identifier (such as a VPC id, ECS cluster name, ECS service name, ALB ARN, target group ARN, or CloudFront distribution id), THE Observability_Module SHALL obtain that identifier exclusively through its own declared input variables.
3. THE Dev_Root SHALL be the only caller that supplies the Observability_Module input variables, sourcing their values from the network, backend, and edge module outputs.
4. THE Observability_Module SHALL NOT reference any resource, data source, or output belonging to the network, backend, or edge modules except through its declared input variables.
5. THE network module, THE Backend_Module, and THE Edge_Module SHALL contain zero references to the Observability_Module, its resources, or its outputs.
6. WHEN `terraform validate` and `terraform plan` are executed on the Dev_Root, THE module graph SHALL complete without reporting a cycle and SHALL preserve the `network → backend → edge` dependency direction with the Observability_Module positioned only as a downstream consumer.

### Requirement 3: Reuse the existing ECS application log group (no duplication)

**User Story:** As an infrastructure engineer, I want the observability module to reuse the backend's existing ECS application log group, so that the ECS log group and its retention have exactly one owner and no duplicate log group is created.

#### Acceptance Criteria

1. THE Observability_Module SHALL NOT declare an `aws_cloudwatch_log_group` resource whose name resolves to `"${name_prefix}-app"` or any value referring to the ECS application log group.
2. WHERE the Observability_Module requires the ECS application log group name, THE Observability_Module SHALL obtain that name from exactly one source, either a Backend_Module output or a single typed input variable carrying the derived `"${name_prefix}-app"` value, and SHALL NOT call `aws_cloudwatch_log_group` to create it.
3. IF the ECS application log group name is supplied to the Observability_Module as an input variable, THEN THE Observability_Module SHALL reject an empty or null value by failing validation before any plan or apply proceeds.
4. THE Backend_Module SHALL remain the sole owner of the ECS application log group resource and its retention, which SHALL equal the integer value of `var.log_retention_days` and SHALL be between 1 and 3653 days inclusive (never 0 and never unlimited).
5. IF the Observability_Module creates a CloudWatch log group that it itself owns for a distinct, separately justified purpose, THEN THE Observability_Module SHALL set a retention period on that log group from a typed integer variable constrained to between 1 and 3653 days inclusive, and SHALL reject a value of 0 or unlimited retention by failing validation.

### Requirement 4: ECS CPU and memory notification alarms

**User Story:** As an operator, I want to be notified when ECS CPU or memory utilization crosses a threshold, so that I can react to compute saturation before it degrades the API that students use during assessments.

#### Acceptance Criteria

1. THE Observability_Module SHALL create a `CPU_Alarm` on the ECS service CPU utilization metric (namespace `AWS/ECS`, metric `CPUUtilization`, statistic `Average`) dimensioned by `ClusterName` from `ecs_cluster_name` and `ServiceName` from `ecs_service_name`.
2. THE Observability_Module SHALL create a `Memory_Alarm` on the ECS service memory utilization metric (namespace `AWS/ECS`, metric `MemoryUtilization`, statistic `Average`) dimensioned by `ClusterName` from `ecs_cluster_name` and `ServiceName` from `ecs_service_name`.
3. THE Observability_Module SHALL configure the `CPU_Alarm` and the `Memory_Alarm` from typed inputs for the threshold (a utilization percentage input constrained to the range 0 through 100), the evaluation period (a count of consecutive periods, minimum 1), and the metric period (in seconds, a positive CloudWatch-valid value), and SHALL evaluate each alarm with a greater-than-or-equal-to comparison so that the alarm breaches when the statistic meets or exceeds the configured threshold.
4. WHEN the evaluated statistic of the `CPU_Alarm` or the `Memory_Alarm` meets or exceeds its configured threshold across the configured number of evaluation periods, THE Observability_Module alarm SHALL enter the `ALARM` state and invoke its configured `Alarm_Actions`.
5. THE `CPU_Alarm` and the `Memory_Alarm` SHALL be notification-and-visibility alarms that are distinct from the Backend_Module autoscaling policy, and THE Observability_Module SHALL NOT create or modify any autoscaling policy or scalable target.

### Requirement 5: ALB unhealthy-host alarm

**User Story:** As an operator, I want to be notified when the ALB reports unhealthy application targets, so that I know the API is losing capacity to serve students taking assessments.

#### Acceptance Criteria

1. THE Observability_Module SHALL create an `Unhealthy_Host_Alarm` on the metric `UnHealthyHostCount` (namespace `AWS/ApplicationELB`, statistic `Maximum`) dimensioned by the Target_Group ARN suffix (`TargetGroup`) and the Internal_ALB ARN suffix (`LoadBalancer`).
2. THE Observability_Module SHALL obtain the Target_Group ARN suffix and the Internal_ALB ARN suffix without hardcoding, from backend module outputs or by deriving the suffix from the full ARN.
3. THE Observability_Module SHALL expose a configurable threshold input for the `Unhealthy_Host_Alarm` that accepts an integer count from 1 to 100 inclusive, defaulting to 1 unhealthy host.
4. THE Observability_Module SHALL expose a configurable period input (in seconds, one of 10, 30, or any multiple of 60 from 60 to 86400 inclusive, defaulting to 60) and a configurable evaluation-periods input (an integer from 1 to 100 inclusive, defaulting to 2) for the `Unhealthy_Host_Alarm`.
5. WHEN the `UnHealthyHostCount` value is greater than or equal to the configured threshold for the configured number of consecutive evaluation periods, THE Observability_Module SHALL transition the `Unhealthy_Host_Alarm` to the ALARM state and send a notification to the configured SNS topic.
6. IF no datapoints are reported for the `UnHealthyHostCount` metric during an evaluation period, THEN THE Observability_Module SHALL treat the missing data as not breaching so that the `Unhealthy_Host_Alarm` does not enter the ALARM state solely due to absent data.

### Requirement 6: ALB target-group 5xx error alarm

**User Story:** As an operator, I want to be notified when application targets return server errors, so that I can respond to failures that break assessment submissions originating in the application.

#### Acceptance Criteria

1. THE Observability_Module SHALL create a `Target_5xx_Alarm` on the metric `HTTPCode_Target_5XX_Count` (namespace `AWS/ApplicationELB`) dimensioned by the Target_Group ARN suffix (`TargetGroup`) and the Internal_ALB ARN suffix (`LoadBalancer`).
2. THE Observability_Module SHALL expose a configurable threshold input for the `Target_5xx_Alarm` accepting an integer from 1 to 100000 with a default of 5, representing the target 5xx response count that triggers the alarm.
3. THE Observability_Module SHALL expose a configurable evaluation-periods input for the `Target_5xx_Alarm` accepting an integer from 1 to 100 with a default of 2, and a period input accepting one of the CloudWatch-supported values 10, 30, or any multiple of 60 up to 86400 seconds with a default of 300 seconds.
4. THE Observability_Module SHALL configure the `Target_5xx_Alarm` to use the `Sum` statistic, the comparison operator greater-than-or-equal-to the threshold, and the `missing` treatment of missing data as `notBreaching`.
5. WHEN the `Sum` of `HTTPCode_Target_5XX_Count` is greater than or equal to the configured threshold for the configured number of consecutive evaluation periods, THE Observability_Module SHALL transition the `Target_5xx_Alarm` to the ALARM state and publish a notification to the configured SNS topic.

### Requirement 7: ALB (ELB) 5xx error alarm

**User Story:** As an operator, I want to be notified when the load balancer itself returns server errors, so that I can distinguish load-balancer-level failures from application failures while students are mid-session.

#### Acceptance Criteria

1. THE Observability_Module SHALL create an `ELB_5xx_Alarm` on the metric `HTTPCode_ELB_5XX_Count` in namespace `AWS/ApplicationELB` using statistic `Sum`, dimensioned solely by the Internal_ALB ARN suffix (dimension `LoadBalancer`) with no additional dimensions.
2. THE Observability_Module SHALL expose a configurable threshold input for the `ELB_5xx_Alarm` that accepts an integer greater than or equal to 1, defaulting to a small DEV value, and SHALL use the greater-than-or-equal-to comparison operator against the metric `Sum`.
3. THE Observability_Module SHALL expose a configurable evaluation-periods input (integer from 1 to 100, default 2) and a configurable period input (a CloudWatch-valid duration in seconds, default 300) for the `ELB_5xx_Alarm`.
4. THE `ELB_5xx_Alarm` SHALL treat missing data as `notBreaching`.
5. THE Observability_Module SHALL create the `ELB_5xx_Alarm` as a separate Terraform resource distinct from the `Target_5xx_Alarm`.

### Requirement 8: CloudWatch dashboard

**User Story:** As an operator, I want a single dashboard showing application and infrastructure metrics, so that I can assess the health of the assessment platform at a glance.

#### Acceptance Criteria

1. THE Observability_Module SHALL create exactly one `Dashboard` (`aws_cloudwatch_dashboard`) whose name is derived from the `Name_Prefix` input and SHALL NOT create a second dashboard resource.
2. THE `Dashboard` SHALL include a widget for ECS service CPU utilization and a widget for ECS service memory utilization, each dimensioned by both `ClusterName` and `ServiceName` values supplied through module inputs or references.
3. THE `Dashboard` SHALL include separate widgets for ALB request count (`RequestCount`), ALB target 5xx count (`HTTPCode_Target_5XX_Count`), ALB load-balancer 5xx count (`HTTPCode_ELB_5XX_Count`), and Target_Group `HealthyHostCount`, each dimensioned by the Internal_ALB `LoadBalancer` ARN suffix and, where applicable, the Target_Group `TargetGroup` ARN suffix supplied through module inputs or references.
4. WHERE CloudFront dashboard widgets are enabled, THE `Dashboard` SHALL include a CloudFront request-count widget and a CloudFront error-rate widget sourced from the `AWS/CloudFront` namespace, with each such widget configured to read metrics from the `us-east-1` region.
5. IF CloudFront dashboard widgets are not enabled, THEN THE Observability_Module SHALL create the `Dashboard` with the ECS and ALB widgets only and SHALL NOT include any `AWS/CloudFront` widget.
6. THE `Dashboard` SHALL derive every metric dimension value from module input variables or resource references and SHALL NOT contain any hardcoded dimension string literal.

### Requirement 9: Optional SNS notification path, disabled by default

**User Story:** As an operator, I want optional email notifications that are off by default, so that the development environment incurs no notification resources or subscriptions unless I explicitly enable them.

#### Acceptance Criteria

1. THE Observability_Module SHALL expose an `enable_sns` boolean input variable that defaults to `false`.
2. WHILE `enable_sns` is `false`, THE Observability_Module SHALL create exactly zero SNS resources (zero `aws_sns_topic` and zero `aws_sns_topic_subscription`) and SHALL set the `Alarm_Actions` list of every alarm to a list of length 0.
3. WHERE `enable_sns` is `true`, THE Observability_Module SHALL create exactly one `aws_sns_topic` and SHALL set the `Alarm_Actions` list of every alarm to a list of length 1 referencing the ARN of that `aws_sns_topic`.
4. WHERE `enable_sns` is `true` AND the `sns_notification_email` input variable is a non-empty string, THE Observability_Module SHALL create exactly one email `aws_sns_topic_subscription` whose endpoint equals the value of the `sns_notification_email` variable.
5. IF `enable_sns` is `true` AND the `sns_notification_email` input variable is an empty string, THEN THE Observability_Module SHALL create the `aws_sns_topic` and SHALL create zero email subscriptions.
6. THE Observability_Module SHALL declare the `sns_notification_email` input variable with an explicit string type and SHALL NOT assign any default endpoint value hardcoded in module source; the email endpoint SHALL be supplied only through the input variable and no secret value SHALL be stored in Terraform configuration.

### Requirement 10: Configurable thresholds, retention, and cost-conscious DEV defaults

**User Story:** As an infrastructure engineer, I want alarm thresholds and any observability-owned retention to be typed variables with cost-conscious development defaults, so that DEV monitoring is tuned without editing module source and incurs minimal recurring cost.

#### Acceptance Criteria

1. THE Observability_Module SHALL expose a typed input variable with an explicit type and a non-empty description for every alarm threshold, every alarm evaluation period, and every metric period it uses, such that no threshold, evaluation period, or metric period is a literal constant in module source.
2. THE Observability_Module SHALL assign each threshold, evaluation period, and metric period variable a cost-conscious DEV default, where evaluation period count defaults to between 1 and 5 periods inclusive and metric period defaults to a CloudWatch-supported value between 60 and 300 seconds inclusive.
3. WHERE the Observability_Module creates a CloudWatch log group, THE Observability_Module SHALL expose a typed retention variable whose DEV default is a finite CloudWatch Logs retention value between 1 and 30 days inclusive, and SHALL NOT set retention to never-expire (0 or unset).
4. IF a numeric input is supplied with a value outside its permitted bounded range, THEN THE Observability_Module SHALL reject the configuration during Terraform validation with a message indicating the invalid variable and its permitted range.
5. THE Observability_Module SHALL constrain every threshold variable to non-negative values and every retention variable to a value accepted by CloudWatch Logs via Terraform variable validation.
6. THE Observability_Module SHALL define the DEV alarm set such that every alarm maps to exactly one stated operational reason drawn from compute saturation, lost API capacity, or server errors affecting students, and SHALL NOT define an alarm lacking such a stated reason.

### Requirement 11: Backend output interface for ALB dimensions (additive, non-breaking)

**User Story:** As an infrastructure engineer, I want the backend module to expose the ALB and target-group dimension values the observability module needs, so that observability obtains them through module outputs instead of hardcoding or reaching across module boundaries.

#### Acceptance Criteria

1. THE Backend_Module SHALL expose an `alb_arn_suffix` output whose value is the Internal_ALB ARN suffix (format `app/<name>/<id>`) derived from the Internal_ALB resource reference and not from a hardcoded string.
2. THE Backend_Module SHALL expose a `target_group_arn_suffix` output whose value is the Target_Group ARN suffix (format `targetgroup/<name>/<id>`) derived from the Target_Group resource reference and not from a hardcoded string.
3. WHERE the Observability_Module needs the ECS application log group name, THE Backend_Module SHALL expose an `ecs_log_group_name` output equal to the existing `aws_cloudwatch_log_group.app` name (`"${name_prefix}-app"`), OR the Dev_Root SHALL supply that derived name to the Observability_Module as a typed input; in either case the name SHALL NOT be hardcoded in the Observability_Module.
4. THE backend output change SHALL retain every pre-existing backend output (`ecr_repository_url`, `alb_dns_name`, `alb_arn`, `ecs_cluster_name`, `ecs_service_name`) unchanged in name and value, and SHALL add only new outputs.
5. THE backend output change SHALL NOT create, modify, replace, or destroy any existing Backend_Module resource, as confirmed by a `terraform plan` reporting no resource additions, changes, or destructions attributable to the output change.
6. THE Backend_Module SHALL contain no reference to the Observability_Module and SHALL NOT introduce any dependency from the Backend_Module to the Observability_Module.

### Requirement 12: Dev root module wiring and outputs

**User Story:** As an infrastructure engineer, I want the observability module composed in the dev root with inputs sourced from other module outputs and DEV values in tfvars, so that monitoring is wired into the environment without hardcoded identifiers.

#### Acceptance Criteria

1. THE Dev_Root SHALL add exactly one `module "observability"` block in `envs/dev/main.tf` whose `source` is `../../modules/observability`.
2. THE Dev_Root SHALL pass the ECS cluster name, ECS service name, ALB identifier, and target-group identifier to the Observability_Module from `module.backend` outputs, and the CloudFront distribution identifier from `module.edge` outputs, and SHALL NOT pass any of these as literal values.
3. IF any identifier the Observability_Module consumes is written as a literal in `envs/dev/main.tf` or `envs/dev/terraform.tfvars` instead of a module-output reference, THEN the wiring SHALL be considered non-compliant.
4. THE Dev_Root SHALL declare each observability input variable it sets with an explicit type and description in `envs/dev/variables.tf`, assign DEV values in `envs/dev/terraform.tfvars`, and set `enable_sns` to `false`.
5. THE Dev_Root SHALL re-export exactly the observability dashboard name and the SNS topic ARN in `envs/dev/outputs.tf` and SHALL NOT re-export any other observability output.
6. WHILE `enable_sns` is `false`, THE re-exported SNS topic ARN output SHALL resolve to null or empty without causing a Terraform error.
7. THE Dev_Root SHALL NOT place any secret value (such as a connection string, password, token, or API key) as a literal in `envs/dev/terraform.tfvars`.

### Requirement 13: Security and encryption expectations

**User Story:** As a security reviewer, I want observability resources to follow least-exposure, retention, and secret-handling expectations, so that monitoring adds no public exposure, no indefinite log retention, and no plaintext secrets.

#### Acceptance Criteria

1. THE Observability_Module SHALL NOT create any resource that is reachable from the public internet, and SHALL NOT create any resource configured with a public endpoint, a public IP address, or a resource policy granting access to an unrestricted principal (`*`) without a `Condition` scoping access to the owning AWS account or VPC.
2. WHERE the Observability_Module owns a CloudWatch log group, THE Observability_Module SHALL set a `retention_in_days` value from the allowed CloudWatch set (one of 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653) and SHALL NOT leave retention unset (never-expire).
3. IF the Observability_Module declares a variable that carries a secret value, THEN THE Observability_Module SHALL mark that variable with `sensitive = true`.
4. THE Observability_Module SHALL NOT define any Terraform output whose value is or is derived from a secret value.
5. WHERE `enable_sns` is `true`, THE Observability_Module SHALL configure the SNS resource to use AWS-managed encryption and SHALL NOT create or reference a customer-managed KMS key unless a customer-managed KMS key is explicitly required by an input variable.

### Requirement 14: ALB target response-time (latency) alarm

**User Story:** As an operator, I want to be notified when API response latency is high, so that I can react to slow responses that degrade or interrupt a student's live assessment before they turn into timeouts or failed submissions.

#### Acceptance Criteria

1. THE Observability_Module SHALL create a `Latency_Alarm` on the metric `TargetResponseTime` (namespace `AWS/ApplicationELB`, unit seconds) dimensioned by the Target_Group ARN suffix (`TargetGroup`) and the Internal_ALB ARN suffix (`LoadBalancer`).
2. THE Observability_Module SHALL configure the `Latency_Alarm` statistic from a typed input that accepts an extended percentile (for example `p90`, `p95`, or `p99`), defaulting to `p95`, so the alarm reflects tail latency rather than only the average.
3. THE Observability_Module SHALL expose a configurable threshold input for the `Latency_Alarm` expressed in seconds, accepting a non-negative number with a cost-conscious DEV default (for example 2 seconds), and SHALL use the greater-than-or-equal-to comparison operator.
4. THE Observability_Module SHALL expose a configurable evaluation-periods input (integer from 1 to 100, default 3) and a configurable period input (a CloudWatch-valid duration in seconds, default 60) for the `Latency_Alarm`.
5. THE `Latency_Alarm` SHALL treat missing data as `notBreaching` so that absent datapoints in a low-traffic DEV environment or during the `desired_count = 0` bootstrap window do not drive the alarm into the ALARM state.
6. THE `Latency_Alarm` SHALL use the same optional-SNS `alarm_actions` wiring as the other alarms: an empty action list while `enable_sns` is `false`, and the single SNS topic ARN when `enable_sns` is `true`.
7. THE Observability_Module SHALL obtain the Target_Group ARN suffix and the Internal_ALB ARN suffix for the `Latency_Alarm` without hardcoding, from backend outputs.

## Out of Scope

- Staging and production environments (`envs/staging`, `envs/prod`) and any staging or production resources.
- Broader security-operations services — AWS WAF, GuardDuty, CloudTrail, and AWS Config — which belong to a
  separate security-operations scope and are NOT part of this observability monitoring spec unless explicitly
  requested later.
- MongoDB Atlas internal database metrics and alarms. Atlas M0 is an external managed service that is not an
  AWS resource and emits no CloudWatch metrics; no Atlas database widgets or alarms are created.
- An ALB access-log S3 bucket. ALB access logging stays disabled in DEV and no access-log bucket is created
  unless separately justified.
- Creating, modifying, or recreating the ECS application log group, the ECS autoscaling policy, or any
  application resource owned by the network, backend, or edge modules.
- Route 53, custom domains, and custom ACM certificates.
- Running `terraform apply`, creating AWS resources, or modifying Terraform state during this spec.

## Correctness Properties / Verification

This feature is declarative Terraform Infrastructure-as-Code. It defines CloudWatch alarms, a CloudWatch
dashboard, an optional SNS notification path, and additive backend outputs — there is no runtime algorithm or
data transformation whose behavior varies with generated input, so property-based testing does not apply.
Verification is performed through the Terraform workflow and plan inspection:

- **Formatting:** `terraform fmt -check -recursive` reports no changes for the module and the dev root.
- **Validation:** `terraform validate` succeeds for the dev root after the module is wired in.
- **Plan inspection (default DEV, `enable_sns = false`):** `terraform plan` and plan-JSON inspection confirm
  the CPU_Alarm, Memory_Alarm, Unhealthy_Host_Alarm, Target_5xx_Alarm, ELB_5xx_Alarm, Latency_Alarm, and the Dashboard are
  planned; no SNS topic or subscription is planned; and every alarm has empty `alarm_actions`.
- **Plan inspection (SNS enabled):** with `enable_sns = true` and an email endpoint set, plan-JSON inspection
  confirms exactly one SNS topic, the email subscription, and that every alarm references the topic in
  `alarm_actions`.
- **Non-duplication inspection:** plan-JSON inspection confirms the module plans no `aws_cloudwatch_log_group`
  for ECS application logs and no autoscaling policy or scalable target.
- **No-hardcoding inspection:** review confirms all CloudWatch dimension values resolve from module
  inputs/outputs or ARN-suffix derivation, with no hardcoded ARNs, account IDs, names, or dimension strings.
- **Boundary inspection:** review confirms the module creates no application resource and that the backend,
  edge, and network modules contain no reference to the observability module (no circular dependency).

Review of the resulting Terraform plan additionally checks for unexpected resource destruction or
replacement, unintended public exposure, security-group or IAM changes, missing or indefinite log retention,
and resources outside the current DEV scope before any later apply decision.
