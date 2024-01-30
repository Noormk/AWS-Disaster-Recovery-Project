provider "aws" {
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
  region     = var.region
}

resource "aws_s3_bucket" "my_bucket" {
  bucket = var.aws_s3_bucket
  acl    = "private"
}

resource "aws_s3_bucket_object" "index_html" {
  bucket = var.aws_s3_bucket
  key    = "index.html"  

  source = "C:/Users/musam/d/AWS-Disaster-Recovery/index.html"  
}

data "aws_iam_policy_document" "lambda_policy" {
  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]

    resources = ["*"]
  }
}

resource "aws_iam_role" "iam_for_lambda" {
  name = "iam_for_lambda"
  assume_role_policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
      {
        "Action": "sts:AssumeRole",
        "Principal": {
          "Service": "lambda.amazonaws.com"
        },
        "Effect": "Allow",
        "Sid": ""
      }
    ]
  })
}

resource "aws_iam_policy" "lambda_policy" {
  name        = "lambda_policy"
  description = "Policy for AWS Lambda"
  policy      = data.aws_iam_policy_document.lambda_policy.json
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.iam_for_lambda.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

data "archive_file" "lambda_zip1" {
  type        = "zip"
  source_dir  = "C:/Users/musam/d/AWS-Disaster-Recovery/lambda_function/"
  output_path = "C:/Users/musam/d/AWS-Disaster-Recovery/lambda_function/scale-resources.zip"
}

data "archive_file" "lambda_zip2" {
  type        = "zip"
  source_dir  = "C:/Users/musam/d/AWS-Disaster-Recovery/lambda_function/"
  output_path = "C:/Users/musam/d/AWS-Disaster-Recovery/lambda_function/redirect-traffic.zip"
}

data "archive_file" "lambda_zip3" {
  type        = "zip"
  source_dir  = "C:/Users/musam/d/AWS-Disaster-Recovery/lambda_function/"
  output_path = "C:/Users/musam/d/AWS-Disaster-Recovery/lambda_function/replicate-maintaindata.zip"
}

resource "aws_lambda_function" "scale-resources" {
  function_name = "scale-resources"
  handler       = "index.handler"  
  runtime       = "python3.8"
  filename      = "C:/Users/musam/d/AWS-Disaster-Recovery/lambda_function/scale-resources.zip"
  role          = aws_iam_role.iam_for_lambda.arn
}

resource "aws_lambda_function" "redirect-traffic" {
  function_name = "redirect-traffic"
  handler       = "index.handler"  
  runtime       = "python3.8"
  filename      = "C:/Users/musam/d/AWS-Disaster-Recovery/lambda_function/redirect-traffic.zip"
  role          = aws_iam_role.iam_for_lambda.arn
}

resource "aws_lambda_function" "replicate-maintaindata" {
  function_name = "maintain-data-consistency"
  handler       = "index.handler"  
  runtime       = "python3.8"
  filename      = "C:/Users/musam/d/AWS-Disaster-Recovery/lambda_function/replicate-maintaindata.zip"
  role          = aws_iam_role.iam_for_lambda.arn
}

resource "aws_launch_configuration" "my_launch_config" {
  name                 = "AWS-DR-Project-EC2"
  image_id             = "ami-0e5f882be1900e43b"
  instance_type        = var.instance_type
  key_name             = "main-key"

  user_data = <<-EOF
    #!/bin/bash
    sudo apt update -y
    sudo apt install apache2 -y 
    sudo systemctl start apache2
  EOF
}

resource "aws_security_group" "my_security_group" {
  name        = "DR-SG"
  description = "Allow inbound SSH and HTTP traffic"
  vpc_id      = aws_vpc.my_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_vpc" "my_vpc" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "my_subnet_a" {
  vpc_id                  = aws_vpc.my_vpc.id
  cidr_block              = "10.0.0.0/24"
  availability_zone       = "eu-west-2a"
  map_public_ip_on_launch = true
}

resource "aws_subnet" "my_subnet_b" {
  vpc_id                  = aws_vpc.my_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "eu-west-2b"
  map_public_ip_on_launch = true
}

resource "aws_autoscaling_group" "my_asg" {
  name                 = "my-asg"
  min_size             = 1
  max_size             = 3
  desired_capacity     = 2
  launch_configuration = aws_launch_configuration.my_launch_config.name
  vpc_zone_identifier  = [aws_subnet.my_subnet_a.id, aws_subnet.my_subnet_b.id]
}

resource "aws_db_subnet_group" "my_db_subnet_group" {
    name       = "my-db-subnet-group"
    subnet_ids = [aws_subnet.my_subnet_a.id, aws_subnet.my_subnet_b.id]
}

resource "aws_db_instance" "my_db_instance" {
    identifier            = "my-db-instance"
    engine                = "mysql"
    engine_version        = "5.7"
    instance_class        = "db.t2.micro"
    allocated_storage     = 20
    storage_type          = "gp2"
    username              = "admin"
    password              = "password"
    publicly_accessible  = false
    vpc_security_group_ids = [aws_security_group.my_security_group.id]
    db_subnet_group_name  = aws_db_subnet_group.my_db_subnet_group.name

    skip_final_snapshot = true
}

resource "aws_cloudwatch_metric_alarm" "cpu_alarm" {
    alarm_name          = "CPUUtilizationAlarm"
    comparison_operator = "GreaterThanOrEqualToThreshold"
    evaluation_periods  = 2
    metric_name         = "CPUUtilization"
    namespace           = "AWS/EC2"
    period              = 120
    statistic           = "Average"
    threshold           = 80
    alarm_actions = [aws_autoscaling_policy.scale_up_policy.arn]
}

resource "aws_autoscaling_policy" "scale_up_policy" {
  name                   = "ScaleUpPolicy"
  scaling_adjustment    = 1
  cooldown              = 300
  adjustment_type       = "ChangeInCapacity"
  autoscaling_group_name   = aws_autoscaling_group.my_asg.name
}
