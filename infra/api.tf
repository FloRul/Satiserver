data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# Load and modify OpenAPI specification
data "template_file" "api_spec" {
  template = file("${path.module}/api.yaml")
  vars = {
    lambda_invoke_arn = module.instance_control.lambda_function_arn
    region            = data.aws_region.current.name
    account_id        = data.aws_caller_identity.current.account_id
  }
}

# API Gateway REST API using OpenAPI spec
resource "aws_api_gateway_rest_api" "game_server_control" {
  name = "satiserver-control"

  body = data.template_file.api_spec.rendered

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

# API Gateway Stage
resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.prod.id
  rest_api_id   = aws_api_gateway_rest_api.game_server_control.id
  stage_name    = "prod"
}

# API Gateway Deployment
resource "aws_api_gateway_deployment" "prod" {
  rest_api_id = aws_api_gateway_rest_api.game_server_control.id

  triggers = {
    redeployment = sha256(jsonencode(aws_api_gateway_rest_api.game_server_control.body))
  }

  lifecycle {
    create_before_destroy = true
  }
}

# API Key
resource "aws_api_gateway_api_key" "game_server" {
  name = "satiserver-api-key"
}

# Usage Plan
resource "aws_api_gateway_usage_plan" "game_server" {
  name = "satiserver-usage-plan"

  api_stages {
    api_id = aws_api_gateway_rest_api.game_server_control.id
    stage  = aws_api_gateway_stage.prod.stage_name
  }
}

resource "aws_api_gateway_usage_plan_key" "game_server" {
  key_id        = aws_api_gateway_api_key.game_server.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.game_server.id
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = module.instance_control.lambda_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.game_server_control.execution_arn}/*/*"
}

# Output the API URL and key for easy access
output "api_url" {
  value = "${aws_api_gateway_stage.prod.invoke_url}/control"
}

output "api_key" {
  value     = aws_api_gateway_api_key.game_server.value
  sensitive = true
}
