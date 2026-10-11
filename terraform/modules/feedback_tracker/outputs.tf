output "ecr_repository-url" {
  value = aws_ecr_repository.feedback_tracker.repository_url
}

output "feedback_tracker-url" {
  value = "http://${aws_lb.feedback_tracker.dns_name}"
}
