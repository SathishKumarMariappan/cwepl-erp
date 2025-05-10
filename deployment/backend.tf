terraform {
  backend "s3" {
    bucket         = "cwepl-terraform-state-bucket"
    key            = "terraform/deployment/state.tfstate"
    region         = "ap-south-1"
    encrypt        = true
    dynamodb_table = "cwepl-terraform-lock-table"
  }
}