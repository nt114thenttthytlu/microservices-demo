output "public_ip" {
  value = module.jenkins.public_ip
}

output "jenkins_url" {
  value = module.jenkins.jenkins_url
}

output "harbor_url" {
  value = module.jenkins.harbor_url
}

output "harbor_registry" {
  value = module.jenkins.harbor_registry
}