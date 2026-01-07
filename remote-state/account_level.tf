## Example at the account level:
resource "cloudflare_ruleset" "my_app" {
  account_id = var.account_id
  name       = "My app ruleset"
  kind       = "custom"
  phase      = "http_request_firewall_custom"

  rules = [
    {
      action = "skip"
      action_parameters = {
        ruleset = "current"
      }
      description = "Allow Partner Payment Gateway"
      ref         = "allow_partner_payment_gateway"
      expression  = "(ip.src eq 192.0.2.3)"
    },
    {
      action      = "block"
      description = "Block Agent"
      ref         = "block_pet_ventor_agent"
      expression  = "(http.user_agent eq \"Pet-vendor\")"
    }
  ]
}


output "ruleset_id" {
  value = cloudflare_ruleset.my_app.id
}

