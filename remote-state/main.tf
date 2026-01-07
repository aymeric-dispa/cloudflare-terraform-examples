terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5"
    }
  }

  cloud {
    organization = "Aymeric-website"
    hostname     = "app.terraform.io"

    workspaces {
      name = "aymeric-website-terraform-my-app"
    }
  }
}

provider "cloudflare" {

}