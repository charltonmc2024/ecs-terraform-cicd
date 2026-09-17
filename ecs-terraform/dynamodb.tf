# ---------------------------------------------------------------------------
# DynamoDB — Application Tables
#
# Core tables for the tutoring platform.
# All tables use on-demand billing and point-in-time recovery.
#
# Common values such as name_prefix and DynamoDB billing mode are defined
# in locals.tf.
#
# Note: key_schema as a nested block is not supported in hashicorp/aws
# provider v6.62. The top-level hash_key attribute is the correct approach
# for this provider version. The deprecation warning is cosmetic and does
# not affect plan or apply. Revisit when upgrading the provider.
# ---------------------------------------------------------------------------


# ---------------------------------------------------------------------------
# Users — base identity record for both students and tutors
# ---------------------------------------------------------------------------

resource "aws_dynamodb_table" "users" {
  name         = "${local.name_prefix}-users"
  billing_mode = local.dynamodb_common.billing_mode
  hash_key     = "userId"

  attribute {
    name = "userId"
    type = "S"
  }

  attribute {
    name = "email"
    type = "S"
  }

  # Lookup users by email
  global_secondary_index {
    name            = "EmailIndex"
    hash_key        = "email"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = {
    Name      = "${local.name_prefix}-users"
    Component = "database"
  }
}


# ---------------------------------------------------------------------------
# Tutors — tutor profiles and subjects
# ---------------------------------------------------------------------------

resource "aws_dynamodb_table" "tutors" {
  name         = "${local.name_prefix}-tutors"
  billing_mode = local.dynamodb_common.billing_mode
  hash_key     = "tutorId"

  attribute {
    name = "tutorId"
    type = "S"
  }

  attribute {
    name = "subject"
    type = "S"
  }

  # Lookup tutors by subject
  global_secondary_index {
    name            = "SubjectIndex"
    hash_key        = "subject"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = {
    Name      = "${local.name_prefix}-tutors"
    Component = "database"
  }
}


# ---------------------------------------------------------------------------
# Courses — courses offered by tutors
# ---------------------------------------------------------------------------

resource "aws_dynamodb_table" "courses" {
  name         = "${local.name_prefix}-courses"
  billing_mode = local.dynamodb_common.billing_mode
  hash_key     = "courseId"

  attribute {
    name = "courseId"
    type = "S"
  }

  attribute {
    name = "tutorId"
    type = "S"
  }

  # Lookup courses by tutor
  global_secondary_index {
    name            = "TutorCourseIndex"
    hash_key        = "tutorId"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = {
    Name      = "${local.name_prefix}-courses"
    Component = "database"
  }
}


# ---------------------------------------------------------------------------
# Bookings — tutoring session reservations
# ---------------------------------------------------------------------------

resource "aws_dynamodb_table" "bookings" {
  name         = "${local.name_prefix}-bookings"
  billing_mode = local.dynamodb_common.billing_mode
  hash_key     = "bookingId"

  attribute {
    name = "bookingId"
    type = "S"
  }

  attribute {
    name = "studentId"
    type = "S"
  }

  attribute {
    name = "tutorId"
    type = "S"
  }

  # Lookup bookings by student
  global_secondary_index {
    name            = "StudentBookingIndex"
    hash_key        = "studentId"
    projection_type = "ALL"
  }

  # Lookup bookings by tutor
  global_secondary_index {
    name            = "TutorBookingIndex"
    hash_key        = "tutorId"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = {
    Name      = "${local.name_prefix}-bookings"
    Component = "database"
  }
}


# ---------------------------------------------------------------------------
# Classes — scheduled class sessions
# ---------------------------------------------------------------------------

resource "aws_dynamodb_table" "classes" {
  name         = "${local.name_prefix}-classes"
  billing_mode = local.dynamodb_common.billing_mode
  hash_key     = "classId"

  attribute {
    name = "classId"
    type = "S"
  }

  attribute {
    name = "courseId"
    type = "S"
  }

  # Lookup classes by course
  global_secondary_index {
    name            = "CourseClassIndex"
    hash_key        = "courseId"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = {
    Name      = "${local.name_prefix}-classes"
    Component = "database"
  }
}
