provider "aws" {
  region = "us-west-2"
}

# Create the S3 bucket with public access block configurations disabled
resource "aws_s3_bucket" "spa_bucket" {
  bucket = "example-spa-bucket"
}

# Configure static website hosting on S3
resource "aws_s3_bucket_website_configuration" "spa_bucket_website" {
  bucket = aws_s3_bucket.spa_bucket.id

  index_document {
    suffix = "index.html"
  }
}

# Set the S3 bucket policy to allow public access
resource "aws_s3_bucket_policy" "spa_bucket_policy" {
  bucket = aws_s3_bucket.spa_bucket.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = "*",
      Action = "s3:GetObject",
      Resource = "${aws_s3_bucket.spa_bucket.arn}/*"
    }]
  })
}

# Disable public access block for the S3 bucket
resource "aws_s3_bucket_public_access_block" "spa_bucket_public_access_block" {
  bucket = aws_s3_bucket.spa_bucket.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# Upload the index.html file to S3
resource "aws_s3_object" "index" {
  bucket       = aws_s3_bucket.spa_bucket.bucket
  key          = "index.html"
  source       = "./index.html"
  content_type = "text/html"
}

# Create the CloudFront distribution
resource "aws_cloudfront_distribution" "distribution" {
  origin {
    domain_name = aws_s3_bucket.spa_bucket.website_endpoint
    origin_id   = "S3-SPA-Origin"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1", "TLSv1.1", "TLSv1.2"]
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-SPA-Origin"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
    viewer_protocol_policy = "redirect-to-https"
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
}

# Create the IAM Role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "lambda_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

# Attach the basic execution policy to the Lambda role
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Create the Lambda function
resource "aws_lambda_function" "example_lambda" {
  function_name = "exampleFunction"
  handler       = "index.handler"
  runtime       = "nodejs20.x"
  role          = aws_iam_role.lambda_role.arn
  filename      = "./function.zip"
}

# Create the API Gateway
resource "aws_api_gateway_rest_api" "example_api" {
  name        = "exampleAPI"
  description = "Example API Gateway"
}

# Create the resource in API Gateway
resource "aws_api_gateway_resource" "resource" {
  rest_api_id = aws_api_gateway_rest_api.example_api.id
  parent_id   = aws_api_gateway_rest_api.example_api.root_resource_id
  path_part   = "example"
}

# Create the GET method for the resource
resource "aws_api_gateway_method" "method" {
  rest_api_id   = aws_api_gateway_rest_api.example_api.id
  resource_id   = aws_api_gateway_resource.resource.id
  http_method   = "GET"
  authorization = "NONE"
}

# Integrate the GET method with the Lambda function
resource "aws_api_gateway_integration" "integration" {
  rest_api_id            = aws_api_gateway_rest_api.example_api.id
  resource_id            = aws_api_gateway_resource.resource.id
  http_method            = aws_api_gateway_method.method.http_method
  type                   = "AWS_PROXY"
  integration_http_method = "POST"
  uri                    = aws_lambda_function.example_lambda.invoke_arn
}

# Permission for API Gateway to invoke the Lambda function
resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.example_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.example_api.execution_arn}/*/*"
}

# Deploy the API Gateway
resource "aws_api_gateway_deployment" "example_api_deployment" {
  depends_on = [aws_api_gateway_integration.integration]

  rest_api_id = aws_api_gateway_rest_api.example_api.id
  stage_name  = "prod"
}
