# These variables must be placed in a terraform.tfvars file
variable "aws_access_key" {}
variable "aws_secret_key" {}
variable "account_id" {}

terraform {
  required_version = ">= 0.12"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "4.11.0"
    }
  }
}

provider "aws" {
  profile = "default"
  region  = "eu-west-1"
  access_key = "${var.aws_access_key}"
  secret_key = "${var.aws_secret_key}"
}

resource aws_dynamodb_table "temperature" {
    name = "temperature"
    hash_key = "id"
    billing_mode = "PROVISIONED"
    read_capacity = 1
    write_capacity = 1
    attribute {
        name = "id"
        type = "S"
    }    

    tags = {
        Name = "terraform-temperature"
    }
}

# Our lambda function that stores the temperature 
resource "aws_lambda_function" temperature_function {
    filename = "temperature-lambda.zip"
    source_code_hash = filebase64sha256("temperature-lambda.zip")
    function_name = "storeTemperature"
    runtime = "python3.9"
    role = aws_iam_role.temperature_lambda_iam.arn
    handler = "temperature-lambda.lambda_handler"
    depends_on = [
        aws_iam_role_policy_attachment.lambda_logs
    ]

    tags = {
        Name = "terraform-lambda"
    }
}

# Execution role for the lambda 
resource "aws_iam_role" temperature_lambda_iam {
    name = "temperature_lambda_iam"
    assume_role_policy = <<EOF
{
"Version": "2012-10-17",
"Statement": [
    {
    "Action": "sts:AssumeRole",
    "Principal": {
        "Service": "lambda.amazonaws.com"
    },
    "Effect": "Allow",
    "Sid": ""
    }]
}
EOF
}

# Policy that allows lambda to write logs to CloudWatch
resource "aws_iam_policy" lambda_logs_policy {
    name = "lambda_logs_policy"
    path = "/"
    description = "Terraform - allow aws lambda to access CloudWatch logs"
    policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*",
      "Effect": "Allow"
    }
  ]
}
EOF
}

# Attach logging policy to our lambda execution rile
resource "aws_iam_role_policy_attachment" lambda_logs {
    role = aws_iam_role.temperature_lambda_iam.name
    policy_arn =  aws_iam_policy.lambda_logs_policy.arn
}

# Resource policy that allows lambda to access dynamodb
resource "aws_iam_policy" lambda_dynamodb_policy {
  name ="lambda_dynamodb_policy"
  path = "/"
  description = "Terraform - allow aws lambda to access dynamodb"
  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "dynamodb:BatchGetItem",
                "dynamodb:GetItem",
                "dynamodb:Scan",
                "dynamodb:Query",
                "dynamodb:BatchWriteItem",
                "dynamodb:PutItem",
                "dynamodb:UpdateItem",
                "dynamodb:DeleteItem"
            ],
            "Resource": "arn:aws:dynamodb:eu-west-1:303373319351:table/temperature"
        }
    ]
}
EOF
}

# Attach dynamodb access to our lambda execution role
resource "aws_iam_role_policy_attachment" lambda_dynamodb {
    role = aws_iam_role.temperature_lambda_iam.name
    policy_arn =  aws_iam_policy.lambda_dynamodb_policy.arn
}

# Now setup api gateway to allow http request to trigger lambda
resource "aws_api_gateway_rest_api" temperature_api {
    name = "temperature_api"
}

# Create resource and method for api call
resource "aws_api_gateway_resource" temperature {
    parent_id = aws_api_gateway_rest_api.temperature_api.root_resource_id
    path_part = "temperature"
    rest_api_id = aws_api_gateway_rest_api.temperature_api.id
}

resource "aws_api_gateway_method" temperature {
    authorization = "NONE"
    http_method = "POST"
    resource_id = aws_api_gateway_resource.temperature.id 
    rest_api_id = aws_api_gateway_rest_api.temperature_api.id
}

# Make our gateway method trigger the lambda 
resource "aws_api_gateway_integration" integration {
    rest_api_id = aws_api_gateway_rest_api.temperature_api.id
    resource_id = aws_api_gateway_resource.temperature.id 
    http_method = aws_api_gateway_method.temperature.http_method
    integration_http_method = "POST"
    type = "AWS_PROXY"
    uri = aws_lambda_function.temperature_function.invoke_arn
}

# Give lambda permission to be called from api gateway
resource "aws_lambda_permission" gw_lambda {
    statement_id  = "AllowExecutionFromAPIGateway"
    action        = "lambda:InvokeFunction"
    function_name = aws_lambda_function.temperature_function.function_name
    principal = "apigateway.amazonaws.com"
    source_arn = "arn:aws:execute-api:eu-west-1:${var.account_id}:${aws_api_gateway_rest_api.temperature_api.id}/*/${aws_api_gateway_method.temperature.http_method}${aws_api_gateway_resource.temperature.path}"
}

# Deploy gateway to environment 'prod'
resource "aws_api_gateway_deployment" temperature {
  rest_api_id = aws_api_gateway_rest_api.temperature_api.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.temperature.id,
      aws_api_gateway_method.temperature.id,
      aws_api_gateway_integration.integration.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" prod {
    stage_name = "prod"
    deployment_id=aws_api_gateway_deployment.temperature.id
    rest_api_id = aws_api_gateway_rest_api.temperature_api.id
}