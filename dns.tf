variable "zone_id" {}
variable "domain" {}

locals {
  hosts = split("\n", chomp(file("${path.module}/christmas_tree.txt")))
}

resource "cloudflare_dns_record" "xmas" {
  zone_id = var.zone_id
  name    = "xmas.${var.domain}"
  ttl     = 300
  type    = "AAAA"
  comment = "for CyberAgent Developers Advent Calendar 2025"
  content = cidrhost(tolist(aws_network_interface.ec2.ipv6_prefixes)[0], length(local.hosts) * 2 - 1)
  proxied = false
}

resource "cloudflare_dns_record" "tree" {
  for_each = { for host in local.hosts : host => index(local.hosts, host) }

  zone_id = var.zone_id
  name    = "${each.key}.${var.domain}"
  ttl     = 300
  type    = "AAAA"
  comment = "for CyberAgent Developers Advent Calendar 2025"
  content = cidrhost(tolist(aws_network_interface.ec2.ipv6_prefixes)[0], each.value * 2 + 1)
  proxied = false
}

