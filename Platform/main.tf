provider "aws" {
  region = "ap-south-1"
}

#terraform apply -var="github_token=" -lock=false --auto-approve
# S3 Bucket for Terraform State
resource "aws_s3_bucket" "terraform_state" {
  bucket = "cwepl-terraform-state-bucket-infra"
  acl    = "private"

  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }

  tags = {
    Name = "Terraform State Storage"
  }
}

# DynamoDB for Locking
resource "aws_dynamodb_table" "terraform_locks" {
  name         = "cwepl-terraform-lock-table"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name = "Terraform Lock Table"
  }
}

# IAM Role for CodePipeline
resource "aws_iam_role" "codepipeline_role" {
  name = "cwepl-codepipeline-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "codepipeline.amazonaws.com"
      }
    }]
  })
}

# IAM Policy for CodePipeline
resource "aws_iam_role_policy" "codepipeline_policy" {
  name = "cwepl-codepipeline-policy"
  role = aws_iam_role.codepipeline_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["s3:*"]
        Effect   = "Allow"
        Resource = ["${aws_s3_bucket.terraform_state.arn}", "${aws_s3_bucket.terraform_state.arn}/*"]
      },
      {
        Action   = ["codebuild:*"]
        Effect   = "Allow"
        Resource = "*"
      },
      {
        Action   = ["dynamodb:*"]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.terraform_locks.arn
      }
    ]
  })
}

# IAM Role for CodeBuild
resource "aws_iam_role" "codebuild_role" {
  name = "cwepl-codebuild-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "codebuild.amazonaws.com"
      }
    }]
  })
}

# IAM Policy for CodeBuild
resource "aws_iam_role_policy" "codebuild_policy" {
  name = "cwepl-codebuild-policy"
  role = aws_iam_role.codebuild_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["logs:*", "s3:*", "codebuild:*", "dynamodb:*"]
        Effect   = "Allow"
        Resource = "*"
      },
      {
        Action   = ["lambda:*", "apigateway:*", "iam:*", "cloudformation:*"]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

# CodeBuild Project
resource "aws_codebuild_project" "terraform_build" {
  name          = "cwepl-terraform-build"
  description   = "Build project for CWEPL-ERP Terraform deployment"
  service_role  = aws_iam_role.codebuild_role.arn
  build_timeout = 10

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "hashicorp/terraform:1.5.5"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = true

    environment_variable {
      name  = "TF_VERSION"
      value = "1.5.5"
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = file("${path.module}/buildspec.yml")
  }
}

# CodePipeline
resource "aws_codepipeline" "serverless_pipeline" {
  name     = "cwepl-serverless-pipeline"
  role_arn = aws_iam_role.codepipeline_role.arn

  artifact_store {
    location = aws_s3_bucket.terraform_state.bucket
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "GitHub_Source"
      category         = "Source"
      owner            = "ThirdParty"
      provider         = "GitHub"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        Owner      = "SathishKumarMariappan"
        Repo       = "cwepl-erp"
        Branch     = "main"
        OAuthToken = var.github_token
      }
    }
  }

  stage {
    name = "Build"

    action {
      name             = "Terraform_Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["source_output"]
      output_artifacts = ["build_output"]
      version          = "1"

      configuration = {
        ProjectName = aws_codebuild_project.terraform_build.name
      }
    }
  }
}