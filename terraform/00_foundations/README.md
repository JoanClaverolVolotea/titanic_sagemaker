# Terraform 00 Foundations

Base Terraform stack for tutorial phase `00-foundations`.

## What this stack prepares
- AWS provider configuration with mandatory `default_tags`.
- Validation guardrail for profile `data-science-user`.
- Optional creation of the tutorial data bucket:
  - `titanic-data-bucket-939122281183-data-science-user`
- Baseline S3 hardening:
  - versioning,
  - server-side encryption (AES256),
  - public access block,
  - deny insecure transport policy.
- Foundation outputs (account, region, tags, bucket).

## Files
- `versions.tf`: Terraform/AWS versions + S3 backend block.
- `providers.tf`: AWS provider + `default_tags`.
- `variables.tf`: inputs and validations.
- `locals.tf`: mandatory tag map.
- `main.tf`: S3 bucket baseline resources.
- `outputs.tf`: exported values.
- `backend-dev.hcl.example`: sample backend config.
- `terraform.tfvars.example`: sample variable values.

## Usage
```bash
cd terraform/00_foundations

# 1) Optional: copy and adjust variables
cp terraform.tfvars.example terraform.tfvars

# 2) Init backend using your real remote state resources
terraform init -backend-config=backend-dev.hcl.example

# 3) Checks
terraform fmt -check
terraform validate
terraform plan
```

## Notes
- If the tutorial data bucket already exists and is managed elsewhere, set:
  - `create_data_bucket = false`
- Backend bucket and lock table must exist before `terraform init`.
