# ---------------------------------------------------------------------------
# IAM — ECS Task Role
#
# The task execution role (in iam_ecs.tf) lets ECS pull the image and write
# logs.  This task role grants the running application the permissions it
# needs — specifically, DynamoDB access scoped to the project's tables.
# ---------------------------------------------------------------------------

resource "aws_iam_role" "ecs_task_role" {
  name = "${var.environment}-${var.app_name}-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.environment}-${var.app_name}-ecs-task-role"
  }
}

# ---------------------------------------------------------------------------
# DynamoDB policy — scoped to the project's tables only.
# Only the actions the API actually needs are granted (least privilege).
# ---------------------------------------------------------------------------
resource "aws_iam_role_policy" "ecs_task_dynamodb" {
  name = "${var.environment}-${var.app_name}-dynamodb-policy"
  role = aws_iam_role.ecs_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DynamoDBTableAccess"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan",
          "dynamodb:BatchGetItem",
          "dynamodb:BatchWriteItem",
        ]
        Resource = [
          aws_dynamodb_table.users.arn,
          "${aws_dynamodb_table.users.arn}/index/*",
          aws_dynamodb_table.tutors.arn,
          "${aws_dynamodb_table.tutors.arn}/index/*",
          aws_dynamodb_table.courses.arn,
          "${aws_dynamodb_table.courses.arn}/index/*",
          aws_dynamodb_table.bookings.arn,
          "${aws_dynamodb_table.bookings.arn}/index/*",
          aws_dynamodb_table.classes.arn,
          "${aws_dynamodb_table.classes.arn}/index/*",
        ]
      }
    ]
  })
}
