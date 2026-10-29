locals {
  # Single naming base for every edge resource name and Name tag; the prefix is
  # derived once here and never recomputed inline elsewhere.
  name_prefix = "${var.app_name}-${var.environment}"
}
