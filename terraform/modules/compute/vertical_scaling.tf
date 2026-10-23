data "archive_file" "vertical_scaler" {
  type        = "zip"
  source_file = "${path.module}/vertical_scaler.py"
  output_path = "${path.root}/.terraform/vertical_scaler.zip"
}
