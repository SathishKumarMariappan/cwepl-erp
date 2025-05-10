output "s3_bucket_name" {
  value = aws_s3_bucket.terraform_state.bucket
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.terraform_locks.name
}

output "codepipeline_name" {
  value = aws_codepipeline.serverless_pipeline.name
}

output "codebuild_project_name" {
  value = aws_codebuild_project.terraform_build.name
}