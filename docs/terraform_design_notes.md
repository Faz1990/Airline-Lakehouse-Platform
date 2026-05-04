# Terraform Design Notes

## 1. Why secrets are not stored in Terraform state

Secrets are intentionally excluded from Terraform because Terraform state becomes a high-value leak surface. State files are often stored remotely, shared across team members, or accidentally committed, so placing the Event Hubs connection string there would spread sensitive data far beyond the runtime that actually needs it.

In this project, Terraform defines the infrastructure boundary, but the secret value is injected separately into Key Vault after provisioning. That keeps responsibility split correctly: Terraform creates the vault and RBAC, while secret rotation remains an operational task. This also matches production thinking: infrastructure is versioned in code, but secret material is managed through controlled rotation workflows rather than embedded in declarative state.

## 2. What changes for prod vs dev

This Terraform is deliberately tuned for a development environment: fast iteration, low cost, and minimal irreversible settings. In production, the design would harden in four ways.

First, networking and exposure would tighten: private endpoints for Event Hubs and Key Vault, with public access disabled. Second, resilience would increase: zone redundancy where supported, auto-inflate on Event Hubs, and more deliberate throughput planning. Third, security posture would harden: purge protection enabled on Key Vault, diagnostic settings enabled, resource locks applied, and local authentication disabled once the downstream consumer can fully use identity-based auth. Fourth, governance and compliance would strengthen: CMK where required, stronger monitoring, and more explicit separation between deployment identities and runtime identities.

The dev configuration is optimized for learning and evidence generation. The prod configuration is optimized for blast-radius reduction, recoverability, and compliance.

## 3. Why Terraform target state can differ from manually bootstrapped live infrastructure

The Terraform code describes the intended target state for a clean environment, not necessarily the exact path by which the current environment was originally created. In this project, several Azure resources were bootstrapped manually before Terraform was introduced. That is common in real teams: systems often start manually, then get codified later once the design stabilizes.

Because of that, Terraform names or resource relationships may represent the clean, repeatable version of the system rather than a byte-for-byte mirror of the original manual setup. If this were being adopted as the source of truth for an already-running environment, the correct next step would be `terraform import`, not blind `apply`. Import reconciles existing resources into state so Terraform can manage them without recreating or drifting them.

That distinction matters in interviews: Terraform is not just about creating resources, it is about controlling lifecycle safely. Clean target state, import strategy, and drift awareness are part of ownership-level IaC thinking.