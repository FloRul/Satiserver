module "instance_control" {
  source = "terraform-aws-modules/lambda/aws"

  function_name = "game-server-control"
  handler       = "index.handler"
  runtime       = "python3.11"
  architectures = ["x86_64"]
  source_path   = "../src"
  timeout       = 60
  environment_variables = {
    INSTANCE_ID = aws_instance.game_server.id
  }
  layers = [
    "arn:aws:lambda:${data.aws_region.current.name}:017000801446:layer:AWSLambdaPowertoolsPythonV3-python311-x86_64:2"
  ]
  role_name                = "satiserver-control-lambda-role"
  attach_policy_statements = true

  policy_statements = {
    ec2 = {
      effect    = "Allow"
      actions   = ["ec2:StartInstances", "ec2:StopInstances", "ec2:DescribeInstances", "ec2:DescribeInstanceStatus"]
      resources = ["*"]
    }
    logging = {
      effect    = "Allow"
      actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
      resources = ["*"]
    }
  }
}
