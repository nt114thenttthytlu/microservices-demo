resource "aws_ecr_repository" "services" {
    for_each = toset([
    "frontend", "productcatalogservice", "cartservice", "paymentservice",
    "shippingservice", "emailservice", "currencyservice", "adservice",
    "checkoutservice", "recommendationservice", "shoppingassistantservice"
  ])
    name = "${var.name}/${each.key}"
    image_tag_mutability = "MUTABLE"
    
    image_scanning_configuration {
        scan_on_push = true
    }
    
    tags = {
        Name = "${var.name}-services"
        Environment = var.environment
    }
  
}