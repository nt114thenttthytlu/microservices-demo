output "public_ip" {
  value = aws_instance.jenkins.public_ip
}

output "jenkins_url" {
  value = "http://${aws_instance.jenkins.public_ip}:8080"
}

output "harbor_url" {
  value = "http://${aws_instance.jenkins.public_ip}"
}

output "harbor_registry" {
  value = "${aws_instance.jenkins.public_ip}:5000"
}