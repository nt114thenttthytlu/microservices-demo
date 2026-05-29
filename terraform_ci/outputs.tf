output "public_ip" {
  description = "Public IP of the Jenkins/Harbor EC2"
  value       = module.jenkins.public_ip
}

output "jenkins_url" {
  description = "URL to access Jenkins"
  value       = "http://${module.jenkins.public_ip}:8080"
}

output "harbor_url_http" {
  description = "URL to access Harbor (HTTP)"
  value       = "http://${module.jenkins.public_ip}:80"
}

output "harbor_url_https" {
  description = "URL to access Harbor (HTTPS)"
  value       = "https://${module.jenkins.public_ip}:443"
}

output "harbor_registry" {
  description = "Harbor Docker registry address"
  value       = "${module.jenkins.public_ip}:5000"
}

output "ssh_connection" {
  description = "SSH command to connect to EC2"
  value       = "ssh -i <your-key.pem> ubuntu@${module.jenkins.public_ip}"
}