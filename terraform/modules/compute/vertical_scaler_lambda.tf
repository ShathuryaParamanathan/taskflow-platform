resource "aws_iam_role" "vertical_scaler_lambda" {
  name               = "${var.name}-vertical-scaler-lambda-role"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" }, Action = "sts:AssumeRole" }] })
  tags               = var.tags
}
resource "aws_iam_role_policy_attachment" "vertical_scaler_logs" {
  role       = aws_iam_role.vertical_scaler_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
resource "aws_iam_role_policy" "vertical_scaler_ecs" {
  name   = "${var.name}-vertical-scaler-ecs-policy"
  role   = aws_iam_role.vertical_scaler_lambda.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = ["ecs:DescribeServices", "ecs:DescribeTaskDefinition", "ecs:RegisterTaskDefinition"], Resource = "*" }, { Effect = "Allow", Action = ["ecs:UpdateService"], Resource = aws_ecs_service.api.id }, { Effect = "Allow", Action = ["iam:PassRole"], Resource = [aws_iam_role.ecs_task_execution.arn, aws_iam_role.ecs_task.arn], Condition = { StringEquals = { "iam:PassedToService" = "ecs-tasks.amazonaws.com" } } }] })
}
resource "aws_lambda_function" "vertical_scaler" {
  function_name    = "${var.name}-vertical-scaler"
  role             = aws_iam_role.vertical_scaler_lambda.arn
  runtime          = "python3.12"
  handler          = "vertical_scaler.lambda_handler"
  filename         = data.archive_file.vertical_scaler.output_path
  source_code_hash = data.archive_file.vertical_scaler.output_base64sha256
  timeout          = 30
  memory_size      = 128
  environment { variables = { ECS_CLUSTER = aws_ecs_cluster.this.name, ECS_SERVICE = aws_ecs_service.api.name, MAX_TASK_CPU = "512", MAX_TASK_MEMORY = "1024" } }
  tags       = var.tags
  depends_on = [aws_iam_role_policy_attachment.vertical_scaler_logs, aws_iam_role_policy.vertical_scaler_ecs]
}
resource "aws_cloudwatch_metric_alarm" "ecs_cpu_vertical" {
  alarm_name          = "${var.name}-ecs-cpu-vertical-scaling"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Average"
  threshold           = 70
  alarm_description   = "Sustained high CPU utilization triggers TaskFlow vertical scaling"
  treat_missing_data  = "notBreaching"
  dimensions          = { ClusterName = aws_ecs_cluster.this.name, ServiceName = aws_ecs_service.api.name }
  tags                = var.tags
}
resource "aws_cloudwatch_metric_alarm" "ecs_memory_vertical" {
  alarm_name          = "${var.name}-ecs-memory-vertical-scaling"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Average"
  threshold           = 70
  alarm_description   = "Sustained high memory utilization triggers TaskFlow vertical scaling"
  treat_missing_data  = "notBreaching"
  dimensions          = { ClusterName = aws_ecs_cluster.this.name, ServiceName = aws_ecs_service.api.name }
  tags                = var.tags
}
resource "aws_cloudwatch_event_rule" "vertical_scaling" {
  name          = "${var.name}-vertical-scaling-alarm-events"
  description   = "Invoke TaskFlow vertical scaler when its ECS CPU or memory alarm enters ALARM"
  event_pattern = jsonencode({ source = ["aws.cloudwatch"], "detail-type" = ["CloudWatch Alarm State Change"], resources = [aws_cloudwatch_metric_alarm.ecs_cpu_vertical.arn, aws_cloudwatch_metric_alarm.ecs_memory_vertical.arn], detail = { state = { value = ["ALARM"] } } })
  tags          = var.tags
}
resource "aws_cloudwatch_event_target" "vertical_scaling" {
  rule      = aws_cloudwatch_event_rule.vertical_scaling.name
  target_id = "TaskFlowVerticalScaler"
  arn       = aws_lambda_function.vertical_scaler.arn
}
resource "aws_lambda_permission" "vertical_scaling_events" {
  statement_id  = "AllowTaskFlowCloudWatchAlarmEvents"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.vertical_scaler.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.vertical_scaling.arn
}
