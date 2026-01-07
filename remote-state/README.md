# remote-state-example

## Purpose 
This folder demonstrates the use of the `terraform_remote_state` data source to enable cross-team collaboration in a Terraform-managed infrastructure. It outlines a strategy where multiple teams, each owning a separate repository and state file, can securely share and reference resources defined in those states. 
This pattern can be used to facilitate cross-team collaboration, and should be used with a remote state backend.

## 🛠️ Prerequisites / Tools Used

* **Terraform Backend:** Terraform Cloud (or equivalent remote backend supporting `remote` data source access).
* **Cloudflare Provider:** V5


## End Goal
The objective of this solution is to establish a secure and collaborative workflow that allows multiple teams to contribute to a shared infrastructure, specifically by enabling **decoupled ruleset management** in Cloudflare WAF.

In this example, we will:
- Create Cloudflare Rulesets in one repository and output its ID to a state file.
- Use `terraform_remote_state` to fetch and reference that ID from another repository/state.
- Add custom rulesets at the account level and zone level. The solution at the zone level is at the bottom of this README.

### 🌐 Scenario: Network and Application Team Separation

The goal is to allow teams to work in isolation while maintaining a unified security posture.

| Role                    | Team             | Responsibility                                                                                                                                 | Terraform Role               |
| :---------------------- | :--------------- | :--------------------------------------------------------------------------------------------------------------------------------------------- | :--------------------------- |
| **Global Orchestrator** | **Network Team** | Manages global infrastructure and the **Root Ruleset**. Enforces base security and routes traffic to specific app rulesets based on hostnames. | **Consumer** (Reads state)   |
| **App Owner**           | **App Team**     | Manages application-specific security logic (e.g., payment gateways, user-agent blocking). Creates a **Custom Ruleset**.                       | **Producer** (Outputs state) |


---

### Goal

#### List of rulesets
![WAF list](images/WAF-list.png)<br/>
This a screenshot of the account WAF ruleset in the Cloudflare dashboard after our change.
As you can see, once everything is implemented and tf files are applied, we will have 2 rulesets in the WAF account: One ruleset managed by the Network team, and one ruleset managed by the app team. 
You can see the network team repo as being a consumer of the ruleset defined in the App Team repo. Clicking on the second item of the list will lead to the following screen.

#### Ruleset defined by the app team
![App rulset](images/app-ruleset.png)<br/>
The screenshot shows the ruleset defined by the App team. The rules are managed by the app team, whilst the expression (e.g. hostname = my.app.come) is managed by the Network team, allowing the App team to work in isolation and preventing them from interfering with other hosts and application.

## 🚀 Step-by-Step Implementation - Account Level

### Phase 1: App Team
#### 1. Create a ruleset. 

```hcl
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
      ref = "allow_partner_payment_gateway"
      expression  = "(ip.src eq 192.0.2.3)" 
    },
    {
      action      = "block"
      description = "Block Agent"
      ref = "block_pet_ventor_agent"
      expression  = "(http.user_agent eq \"Pet-vendor\")"
    }
  ]
}
```
#### 2. Output your ruleset

Crucial Step: The App Team must output the ID of their ruleset so it is stored in the remote state file.

```hcl
output "ruleset_id" {
  value = cloudflare_ruleset.my_app.id
}
```

#### 3. Run Terraform apply to create your tf resources
Run terraform apply. This creates the resource in Cloudflare and saves the ruleset_id to the remote backend.
Ideally this step would be fully automated and part of your CI/CD pipeline.

Command:
````
terraform apply
````

Result:
<details>
<summary>Click to see Terraform Apply Output</summary>

````text
Terraform will perform the following actions:

  # cloudflare_ruleset.my_app will be created
  + resource "cloudflare_ruleset" "my_app" {
      + account_id   = "8cbbfeb03ed26f06132f430d11c5450d"
      + description  = ""
      + id           = (known after apply)
      + kind         = "custom"
      + last_updated = (known after apply)
      + name         = "My app ruleset"
      + phase        = "http_request_firewall_custom"
      + rules        = [
          + {
              + action            = "skip"
              + action_parameters = {
                  + ruleset = "current"
                }
              + description       = "Allow Partner Payment Gateway"
              + enabled           = true
              + expression        = "(ip.src eq 192.0.2.2)"
              + id                = (known after apply)
              + logging           = (known after apply)
              + ref               = (known after apply)
            },
          + {
              + action            = "block"
              + action_parameters = {}
              + description       = "Block Agent"
              + enabled           = true
              + expression        = "(http.user_agent eq \"Pet-vendor\")"
              + id                = (known after apply)
              + logging           = (known after apply)
              + ref               = (known after apply)
            },
        ]
      + version      = (known after apply)
    }

Plan: 1 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + ruleset_id = (known after apply)

Do you want to perform these actions in workspace "aymeric-website-terraform-my-app"?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value: yes

cloudflare_ruleset.my_app: Creating...
cloudflare_ruleset.my_app: Creation complete after 1s [id=92b0add4db7946d0b945d41eba7e6ac4]

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.

Outputs:
ruleset_id = "92b0add4db7946d0b945d41eba7e6ac4"
````

</details>


### Phase 2: Network Team (The Consumer)
Now that the resource by the App team has been created, the Network team needs to reference it inside their own tf file.

#### 1. Use terraform_remote_state to read the App Team's outputs.
```hcl
data "terraform_remote_state" "my_app_state" {
  backend = "remote"
  config = {
    organization = "Aymeric-website"
    workspaces = {
      name = "aymeric-website-terraform-my-app"
    }
  }
}
```
#### 2. Include the ruleset defined by the app team in the root ruleset
```hcl
  rules = [
    ...,
    {
      action      = "execute"
      description = "Rules defined by the App Team for My App" 
      expression  = "(http.host eq \"my.app.com\") and (cf.zone.plan eq \"ENT\")"
      action_parameters = {
        id = data.terraform_remote_state.my_app_state.outputs.ruleset_id
      }
    },
  ]
```


<details>
<summary>Click to see Terraform file used by the network team</summary>

```hcl
resource "cloudflare_ruleset" "root" {
  account_id = var.account_id
  kind       = "root"
  name       = "All"
  phase      = "http_request_firewall_custom"

  rules = [
    {
      description = "Rules defined by the Network Team for all hosts"
      action      = "execute"
      expression  = "(cf.zone.plan eq \"ENT\")"
      ref         = "network_rules"
      action_parameters = {
        id = cloudflare_ruleset.network.id
      }
    },
    {
      action      = "execute"
      description = "Rules defined by the App Team for My App"
      expression  = "(http.host eq \"my.app.com\") and (cf.zone.plan eq \"ENT\")"
      ref         = "app_rules"
      action_parameters = {
        id = data.terraform_remote_state.my_app_state.outputs.ruleset_id
      }
    },
  ]
}


resource "cloudflare_ruleset" "network" {
  account_id = var.account_id
  kind       = "custom"
  name       = "Block AF"
  phase      = "http_request_firewall_custom"
  rules = [
    {
      action      = "block"
      description = "Block AF"
      enabled     = true
      expression  = "(ip.src.country eq \"AF\")"
      id          = null
      version     = "1"
      ref         = "Block AF"
    }
  ]
}


data "terraform_remote_state" "my_app_state" {
  backend = "remote"
  config = {
    organization = "Aymeric-website"
    workspaces = {
      name = "aymeric-website-terraform-my-app"
    }
  }
}
```

</details>

#### 3. Grant permission to the Network team.
By default, one workspace cannot read another's state. The App Team must explicitly grant access to the Network Team.

Without giving permission, running `terraform apply` will lead to an error looking like the one below.

````
│ Error: Error retrieving state: forbidden
│ 
│ This Terraform run is not authorized to read the state of the workspace 'aymeric-website-terraform-my-app'.
│ Most commonly, this is required when using the terraform_remote_state data source.
│ To allow this access, 'aymeric-website-terraform-my-app' must configure this workspace ('aymeric-website-terraform-account')
│ as an authorized remote state consumer. For more information, see:
│ https://developer.hashicorp.com/terraform/cloud-docs/workspaces/state#accessing-state-from-other-workspaces.
````
Which simply indicates that the workplace 'aymeric-website-terraform-account' needs to be granted access to the workspace 'aymeric-website-terraform-my-app' in order to read its state. 
This part depends on what terraform backend you are using for your terraform state.
See below how I configured mine (with Terraform cloud).

1. Go to https://app.terraform.io/
2. Go to the App team workspace (aymeric-website-terraform-my-app in my example)
3. Select Share with specific workspaces and add the Network Team's workspace.

See below:

![sharing](images/sharing.png)

#### 4. Run terraform apply

### Result 
Once configured, the Cloudflare WAF will contain a modular ruleset structure.

1. The WAF Ruleset List The Network Team's repository acts as the parent container, while the App Team's repository acts as a plug-in.

2. The App Ruleset Details The specific rules (Payment Gateway, User Agent) are managed by the App Team, but the context in which they run (the hostname) is controlled by the Network Team.

### FAQ

- What happens if the app team tries to delete (destroy) a ruleset that is referenced by the network team ?<br/>
`terraform apply` will fail, as demonstrated below:

````text
cloudflare_ruleset.my_app: Destroying... [id=92b0add4db7946d0b945d41eba7e6ac4]
╷
│ Error: failed to make http request
│ 
│ DELETE
│ "https://api.cloudflare.com/client/v4/accounts/8cbbfeb03ed26f06132f430d11c5450d/rulesets/92b0add4db7946d0b945d41eba7e6ac4":
│ 400 Bad Request {
│   "result": null,
│   "success": false,
│   "errors": [
│     {
│       "message": "rulesets referenced by another ruleset cannot be deleted"
│     }
│   ],
│   "messages": []
│ }
````

- What happens if the app team changes their ruleset ? Will the Network team need to do anything for the change to be applied ?<br/>
The change will be applied as soon as the App team runs `terraform apply`.
The Network team is referencing the ruleset via its id, not its content directly - so not change is required.

### Other Considerations
Ensure that only authorized workspaces are granted state access.
There are other (and potentially more secure) ways to share state information between workspaces, depending on the use case and tools/configuration, as explained [here](https://developer.hashicorp.com/terraform/language/state/remote-state-data).

## 🚀 Step-by-Step Implementation - Zone Level
This short section is shows how to implement a similar solution at the zone level. It is very similar (hence why the section is a lot shorter).

#### 1. Create a custom ruleset that will be reused.
This ruleset would typically be added to your App team repo.

The following custom ruleset will only get created but it will still need to be added to an entry point ruleset (a ruleset of kind zone or root) in order to have it deployed to a phase.
See more information [here](https://developers.cloudflare.com/ruleset-engine/about/rulesets/#entry-point-ruleset). 


```hcl
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
```

#### 2. Apply the ruleset

terraform apply

#### 3. Use the ruleset (in the ocnsumer repo)

See the kind 'zone', which is the entry point ruleset.


```hcl
resource "cloudflare_ruleset" "zone" {
  zone_id = "5143a1b2f9f02ac700c4e6912abfe763"
  name       = "My app ruleset - zone - main repo"
  kind       = "zone"
  phase      = "http_request_firewall_custom"

  rules = [
    {
      action      = "execute"
      expression  = "true"
      description = "App Team Ruleset"
      action_parameters = {
        id = data.terraform_remote_state.my_app_state.outputs.ruleset_app_zone_id
      }
    },
    {
      action = "skip"
      action_parameters = {
        ruleset = "current"
      }
      description = "Allow Partner Payment Gateway"
      ref = "allow_partner_payment_gateway"
      expression  = "(ip.src eq 192.0.2.3)" 
    },
    {
      action      = "block"
      description = "Block Agent"
      ref = "block_pet_ventor_agent"
      expression  = "(http.user_agent eq \"Pet-vendor-main\")"
    }
  ]
}

data "terraform_remote_state" "my_app_state" {
  backend = "remote"
  config = {
    organization = "Aymeric-website"
    workspaces = {
      name = "aymeric-website-terraform-my-app"
    }
  }
}
```

#### 4. Result
As explained in the [doc](https://developers.cloudflare.com/waf/custom-rules/custom-rulesets/), Currently, the Cloudflare dashboard does not support working with custom rulesets at the zone level. You will need to use the Cloudflare API to configure or deploy these rulesets.
Find below the result when looking at the dashboard:
![Security Rules - zone level](images/security-rules.png)
As you can see, we can see the ruleset description but we cannot see the individuals rules etc.

Find below the result when calling the [API](https://developers.cloudflare.com/api/resources/rulesets/), which gives a lot more information about the ruleset deployed

Entry point ruleset:
```json
{
	"result": {
		"description": "",
		"id": "e0ed9274cf9f4a69bd1752bfddd23fcd",
		"kind": "zone",
		"last_updated": "2026-01-07T15:43:11.852761Z",
		"name": "My app ruleset - zone - main repo",
		"phase": "http_request_firewall_custom",
		"rules": [
			{
				"action": "execute",
				"action_parameters": {
					"id": "ea35b0e0f95f4f42810e4b3d4959313f",
					"version": "latest"
				},
				"description": "App Team Ruleset",
				"enabled": true,
				"expression": "true",
				"id": "9131b971bb6e4dc2805698a4946089df",
				"last_updated": "2026-01-07T15:43:11.852761Z",
				"ref": "9131b971bb6e4dc2805698a4946089df",
				"version": "1"
			},
			{
				"action": "skip",
				"action_parameters": {
					"ruleset": "current"
				},
				"description": "Allow Partner Payment Gateway",
				"enabled": true,
				"expression": "(ip.src eq 192.0.2.3)",
				"id": "a7a12bc4dbe64c329c38c446373130da",
				"last_updated": "2026-01-07T12:50:39.260759Z",
				"logging": {
					"enabled": true
				},
				"ref": "allow_partner_payment_gateway",
				"version": "1"
			},
			{
				"action": "block",
				"description": "Block Agent",
				"enabled": true,
				"expression": "(http.user_agent eq \"Pet-vendor-main\")",
				"id": "6c2491f1c1e04dff8c0dd757f77acb8b",
				"last_updated": "2026-01-07T12:50:39.260759Z",
				"ref": "block_pet_ventor_agent",
				"version": "1"
			}
		],
		"source": "firewall_custom",
		"version": "4"
	},
	"success": true,
	"errors": [],
	"messages": []
}
```

App team custom ruleset:
```json
{
	"result": {
		"description": "",
		"id": "ea35b0e0f95f4f42810e4b3d4959313f",
		"kind": "custom",
		"last_updated": "2026-01-07T15:57:31.927947Z",
		"name": "My app ruleset - zone - from App team",
		"phase": "http_request_firewall_custom",
		"rules": [
			{
				"action": "block",
				"description": "My App rule - from App team",
				"enabled": true,
				"expression": "(http.user_agent eq \"Pet-vendor-sub\")",
				"id": "b8c22b4f40a648ff9d208a54fa807bd2",
				"last_updated": "2026-01-07T13:01:45.628423Z",
				"ref": "block_pet_ventor_agent",
				"version": "2"
			}
		],
		"source": "firewall_custom",
		"version": "3"
	},
	"success": true,
	"errors": [],
	"messages": []
}
```

And to prove that my rules are being taken into account, see below an example of a trace with the header
` "User-Agent": "Pet-vendor-sub" `. ![trace-result](images/trace-result.png).