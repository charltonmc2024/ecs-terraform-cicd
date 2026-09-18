
locals {

  name_prefix = "${var.app_name}-${var.environment}"



  dynamodb_common = {
    billing_mode = "PAY_PER_REQUEST"
  }
}



