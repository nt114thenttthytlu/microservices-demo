output "public_ip" {
  value = aws_eip.eip.public_ip
}

output "jenkins_url" {
  value = "http://${aws_eip.eip.public_ip}:8080"
}

output "harbor_url" {
  value = "http://${aws_eip.eip.public_ip}"
}

output "harbor_registry" {
  value = "${aws_eip.eip.public_ip}:5000"
}