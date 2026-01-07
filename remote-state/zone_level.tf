## Example at the zone level
resource "cloudflare_ruleset" "my_app_zone_sub" {
  zone_id = "5143a1b2f9f02ac700c4e6912abfe763"
  name    = "My app ruleset - zone - from App team"
  kind    = "custom"
  phase   = "http_request_firewall_custom"


  rules = [
    {
      action      = "block"
      description = "My App rule - from App team"
      ref         = "block_pet_ventor_agent"
      expression  = "(http.user_agent eq \"Pet-vendor-sub\")"
    }
  ]
}

output "ruleset_app_zone_id" {
  value = cloudflare_ruleset.my_app_zone_sub.id
}