# AI Usage Log

This log records AI assistance used while preparing the assignment. Entries must
be updated whenever another AI prompt is used.

## Entry 1 - Assignment Planning

**Date:** 2026-06-19

**Tool:** OpenAI Codex

**Exact prompt:**

> You are acting as a senior DevOps engineer reviewing a technical assignment.
>
> I need to complete a DevOps assignment for a UK payroll platform handling sensitive employee PII, bank details, payroll records, and employer data.
>
> The required deliverables are:
> - Terraform code to deploy AWS infrastructure
> - VPC with public/private subnets across at least 2 AZs
> - EC2 instances for Companies, Bureaus, and Employees portals
> - RDS PostgreSQL in private subnet
> - S3 bucket with versioning
> - IAM roles scoped per tenant type
> - Security Groups and NACLs isolating tenant environments
> - Multi-tenancy architecture documentation
> - Secrets management
> - Encryption at rest and in transit
> - GitHub Actions CI/CD for Dockerized app deployment to EC2 via SSH or SSM
> - CloudWatch alarms, logs, SNS alerts
> - Incident response runbook
> - UK GDPR compliance considerations
> - AI usage log
>
> Do not generate code yet.
>
> First:
> 1. Break the assignment into deliverables.
> 2. Propose a secure repository structure.
> 3. Identify security-critical design decisions.
> 4. Identify trade-offs I should explicitly explain in the README.
> 5. Recommend an implementation order.
>
> Assume I may not deploy live AWS resources, so the output must be valid and well-structured IaC, but deployment is optional.

**Response or key output used:**

The response decomposed the assignment into Terraform, documentation,
application, CI/CD, monitoring, runbook, compliance, and AI-log deliverables. It
proposed a modular repository structure, identified the distinction between
portal type and actual customer tenant, recommended PostgreSQL RLS and SSM
deployment, listed production-versus-assignment trade-offs, and proposed a
security-first implementation order.

**Changes, adaptations, or rejections:**

- Retained the recommendation to make tenancy and threat-model decisions before
  Terraform implementation.
- Retained the warning that EC2-per-portal is not customer-level isolation.
- Deferred all implementation because the prompt explicitly requested planning
  only.
- Refined the network recommendation in Entry 2 after applying the assignment's
  strict service constraint: private EC2 cannot use SSM without NAT or VPC
  endpoints.

## Entry 2 - Architecture Decision Record

**Date:** 2026-06-19

**Tool:** OpenAI Codex

**Exact prompt:**

> Create an Architecture Decision Record for this assignment.
>
> Context:
> The platform is a UK payroll system handling sensitive PII and bank data. It has three portals:
> - Companies
> - Bureaus
> - Employees
>
> The assignment requires compute-layer isolation using one EC2 instance per tenant type and AWS-level access boundaries.
>
> I want a security-first but assignment-feasible design using AWS Free Tier friendly services only:
> - EC2 t2.micro or t3.micro
> - RDS PostgreSQL db.t3.micro
> - S3
> - IAM
> - CloudWatch
> - SNS
> - SSM Parameter Store or Secrets Manager
>
> Please propose and justify:
> 1. AWS region choice for UK/EU data residency.
> 2. VPC design.
> 3. Public/private subnet strategy.
> 4. Why EC2 instances should be isolated per portal type.
> 5. RDS placement and database isolation model.
> 6. S3 prefix and bucket policy model.
> 7. IAM role boundaries.
> 8. Security group and NACL strategy.
> 9. Secrets management approach.
> 10. CI/CD deployment approach.
>
> Be explicit about trade-offs and explain what would be improved in production.

**Response or key output used:**

Created `docs/decisions/ADR-0001-security-first-aws-architecture.md`. The ADR
selects `eu-west-2`, portal-specific public subnet groups for the constrained
assessment, private RDS subnets, shared-schema PostgreSQL with forced RLS,
portal-and-tenant S3 prefixes, distinct IAM roles, security-group-first network
controls, SSM SecureString parameters, and GitHub OIDC plus S3/SSM deployment.
It records alternatives, residual risks, production improvements, and acceptance
tests.

**Changes, adaptations, or rejections:**

- Used public EC2 instances only for the constrained assessment because private
  instances require NAT or VPC endpoints to reach SSM and CloudWatch.
- Required no SSH and HTTPS-only ingress to reduce the resulting exposure.
- Kept RDS entirely private and used separate portal subnet/NACL groups.
- Rejected any claim that three portal IAM roles isolate individual customers;
  database RLS and application authorization remain mandatory.
- Selected SSM Parameter Store for assignment feasibility and documented Secrets
  Manager rotation as the production improvement.
- Used a separate S3 deployment-artifact bucket rather than mixing executable
  artifacts with payroll documents.

## Entry 3 - Terraform Repository Scaffold

**Date:** 2026-06-19

**Tool:** OpenAI Codex

**Exact prompt:**

> Generate a Terraform repository scaffold for the assignment.
>
> Requirements:
> - Use Terraform, not CloudFormation.
> - Use AWS provider.
> - Organize files clearly.
> - Do not hardcode credentials.
> - Use variables for region, environment, CIDR ranges, instance types, DB name, and retention periods.
> - Include:
>   - main.tf
>   - variables.tf
>   - outputs.tf
>   - versions.tf
>   - terraform.tfvars.example
>   - modules/networking
>   - modules/security
>   - modules/compute
>   - modules/database
>   - modules/storage
>   - modules/iam
>   - modules/monitoring
>
> Generate only the initial file structure and minimal valid Terraform skeleton first.
>
> Do not overcomplicate it. This is for a technical assignment where clarity, security reasoning, and maintainability matter.

**Response or key output used:**

Created the root Terraform scaffold under `infrastructure/terraform`, including
AWS provider constraints, shared tags, typed and validated non-secret variables,
root module calls, a non-sensitive summary output, and an example tfvars file.
Created `main.tf`, `variables.tf`, and `outputs.tf` placeholders for networking,
security, compute, database, storage, IAM, and monitoring modules.

**Changes, adaptations, or rejections:**

- Kept module resource files intentionally empty except for scope comments; this
  step defines structure and contracts rather than prematurely implementing AWS
  resources.
- Used portal-specific public CIDR lists to remain consistent with ADR-0001.
- Added validation for assignment-approved EC2 sizes and supported retention
  ranges.
- Preserved the repository's existing `.gitignore` and added exclusions for
  plans, environment files, private keys, and real tfvars while allowing
  `terraform.tfvars.example`.
- Did not add credentials, database passwords, secret values, backend state, or
  deployment-specific account identifiers.

## Entry 4 - Terraform Networking Module

**Date:** 2026-06-19

**Tool:** OpenAI Codex

**Exact prompt:**

> # Context from my IDE setup:
>
> ## Open tabs:
> - AI_USAGE_LOG.md: ssagnik/Ocean_Across_DevOps_Assignment/AI_USAGE_LOG.md
>
> ## My request for Codex:
> Now implement the Terraform networking module.
>
> Requirements:
> - One VPC.
> - At least two Availability Zones.
> - Public subnets for internet-facing access or bastion/load-balancing placeholder.
> - Private subnets for EC2 application instances and RDS.
> - Internet Gateway for public subnets.
> - Route tables for public and private subnets.
> - No NAT Gateway because I want to stay Free Tier conscious and avoid unnecessary cost.
> - Add comments explaining the security purpose of each component.
> - Outputs should expose VPC ID, public subnet IDs, private subnet IDs, and CIDR blocks.
>
> Important:
> The platform handles sensitive payroll and bank data, so private resources must not be publicly routable.

**Response or key output used:**

Implemented the networking module with one VPC, dynamic selection of two AZs,
two public ingress-placeholder subnets, one private application subnet per
portal, and two private database subnets. Added an internet gateway and public
default route, while private application and database route tables retain only
VPC-local routing. Added root and module outputs for VPC, subnet IDs, and CIDRs.

**Changes, adaptations, or rejections:**

- Replaced the scaffold's portal-specific public subnet model with two public
  ingress placeholders and moved portal compute to private subnets.
- Separated application and database private subnet tiers so future NACLs and
  route changes do not collapse their boundaries.
- Disabled automatic public IP assignment in every subnet, including public
  placeholders; public resources must opt in explicitly.
- Rejected NAT Gateway creation to avoid continuous assignment cost.
- Documented that no-NAT private EC2 instances cannot currently reach SSM, S3,
  CloudWatch public endpoints, package repositories, or GitHub. The earlier ADR
  was amended so it no longer claims that SSM deployment works in this topology.
- Ran Terraform 1.10.5 formatting and validation with the signed AWS provider
  selected in `.terraform.lock.hcl`; the final configuration passed both checks.

## Entry 5 - Security Groups and Network ACLs

**Date:** 2026-06-19

**Tool:** OpenAI Codex

**Exact prompt:**

> # Context from my IDE setup:
>
> ## Open tabs:
> - AI_USAGE_LOG.md: ssagnik/Ocean_Across_DevOps_Assignment/AI_USAGE_LOG.md
>
> ## My request for Codex:
> Implement Terraform security groups and network ACLs for this payroll platform.
>
> Tenant portal types:
> - company
> - bureau
> - employee
>
> Requirements:
> - Each portal EC2 instance should have its own security group.
> - RDS should have its own security group.
> - RDS must not be publicly accessible.
> - Only the relevant application security groups may connect to PostgreSQL on port 5432.
> - Restrict SSH access. Prefer using SSM Session Manager conceptually; if SSH is included, make the allowed CIDR configurable and warn against 0.0.0.0/0.
> - Add NACLs to demonstrate subnet-level restrictions between tenant environments.
> - Include comments explaining how this creates a second boundary if application tenant logic fails.
>
> Keep the rules understandable for an evaluator.

**Response or key output used:**

Implemented separate Companies, Bureaus, and Employees application security
groups, a future load-balancer security group, and a PostgreSQL security group.
RDS ingress uses application security-group references on port 5432 rather than
CIDRs. Implemented one NACL per portal application subnet and one database NACL,
including explicit cross-portal denies and stateless return rules.

**Changes, adaptations, or rejections:**

- Preserved the repository's plural portal keys (`companies`, `bureaus`, and
  `employees`) while implementing the three requested portal boundaries.
- Disabled SSH by default with `ssh_allowed_cidr = null`; an optional CIDR must
  be valid and cannot be `0.0.0.0/0`.
- Used security-group references for application-to-RDS traffic so public and
  broad VPC CIDRs cannot reach PostgreSQL.
- Added only PostgreSQL and VPC DNS application egress in the base topology.
- Added explicit NACL denies between portal subnets even though unmatched NACL
  traffic is already denied, making the second boundary clear to reviewers.
- Documented that network controls cannot isolate rows in shared PostgreSQL;
  forced RLS and scoped database roles are still required.
- Corrected a duplicate Terraform resource label found by the first validation
  run. The formatted final configuration passes `terraform validate`.

## Entry 6 - Terraform Compute Module

**Date:** 2026-06-19

**Tool:** OpenAI Codex

**Exact prompt:**

> # Context from my IDE setup:
>
> ## Open tabs:
> - AI_USAGE_LOG.md: ssagnik/Ocean_Across_DevOps_Assignment/AI_USAGE_LOG.md
> - ADR-0001-security-first-aws-architecture.md: ssagnik/Ocean_Across_DevOps_Assignment/docs/decisions/ADR-0001-security-first-aws-architecture.md
>
> ## My request for Codex:
> Implement the Terraform compute module.
>
> Requirements:
> - Create three EC2 instances:
>   - company portal backend
>   - bureau portal backend
>   - employee portal backend
> - Use t2.micro or t3.micro.
> - Place instances in private subnets.
> - Attach separate IAM instance profiles for each portal type.
> - Attach separate security groups for each portal type.
> - Add user_data that installs Docker and prepares a placeholder app directory.
> - Do not put secrets in user_data.
> - Use tags to clearly identify environment, portal type, and ownership.
> - Output private IPs and instance IDs.
>
> The goal is to reflect compute-layer isolation between the three user types.

**Response or key output used:**

Implemented one private EC2 instance for each of the Companies, Bureaus, and
Employees portal maps. Each receives its matching private subnet, security
group, and IAM instance profile. Added Amazon Linux 2023 discovery with an
optional pinned AMI, encrypted gp3 root volumes, required IMDSv2, portal and
ownership tags, secret-free Docker bootstrap, and keyed ID/private-IP outputs.

**Changes, adaptations, or rejections:**

- Preserved the repository's plural portal keys while representing the three
  requested portal types.
- Added minimal separate EC2 IAM roles and instance profiles in the IAM module
  because the compute module requires real profile names. Only the AWS-managed
  SSM core policy is attached at this stage; portal data policies remain a
  separate IAM implementation step.
- Omitted public IPs and SSH key pairs. SSM permissions are present, but the
  current no-NAT topology still needs SSM endpoints or controlled egress.
- Prepared the portal directory before attempting Docker installation and kept
  credentials and application secrets out of user data.
- Documented that `dnf install docker` cannot complete without package-repository
  connectivity; a pre-baked AMI is the production preference.
- Added a contract check requiring instance-type, subnet, security-group, and
  instance-profile maps to use identical portal keys.
- Verified the AL2023 AMI naming pattern and Docker package availability against
  current AWS documentation.
- Ran recursive Terraform formatting and validation successfully.

## Entry 7 - Terraform RDS PostgreSQL Module

**Date:** 2026-06-19

**Tool:** OpenAI Codex

**Exact prompt:**

> # Context from my IDE setup:
>
> ## Open tabs:
> - AI_USAGE_LOG.md: ssagnik/Ocean_Across_DevOps_Assignment/AI_USAGE_LOG.md
> - ADR-0001-security-first-aws-architecture.md: ssagnik/Ocean_Across_DevOps_Assignment/docs/decisions/ADR-0001-security-first-aws-architecture.md
>
> ## My request for Codex:
> Implement the Terraform database module for RDS PostgreSQL.
>
> Requirements:
> - RDS PostgreSQL db.t3.micro.
> - Private subnet group only.
> - Public accessibility must be false.
> - Storage encryption enabled.
> - Credentials must not be hardcoded.
> - Use AWS Secrets Manager or SSM Parameter Store to reference database credentials.
> - Add backup retention suitable for an assignment.
> - Add deletion protection as a variable, default true for production and false for local assignment testing.
> - Security group must allow PostgreSQL only from the application security groups.
> - Output endpoint carefully without exposing credentials.
>
> Also include comments explaining how the database is protected at rest and from public internet access.

**Response or key output used:**

Implemented an encrypted Single-AZ RDS PostgreSQL `db.t3.micro` instance in the
two private database subnets, attached only to the existing RDS security group.
Added forced PostgreSQL TLS, seven-day backups, environment-aware deletion
protection, production final-snapshot behavior, RDS-managed Secrets Manager
credentials, and sensitive endpoint/secret-ARN outputs.

**Changes, adaptations, or rejections:**

- Used PostgreSQL 16 as a major-version default after verifying current RDS
  support in AWS documentation; minor upgrades remain automatic.
- Rejected reading an SSM SecureString value through Terraform because the
  plaintext password would be retained in state.
- Enabled `manage_master_user_password` so RDS generates, stores, and rotates
  the password in Secrets Manager. Terraform outputs only the secret ARN.
- Required a configurable, non-secret master username rather than embedding it
  in the module.
- Hardcoded `publicly_accessible = false`, encrypted storage, private subnet
  group usage, and the dedicated RDS security-group attachment as defense in
  depth.
- Resolved null deletion protection to true for `production` and false for
  assignment environments, while allowing an explicit override.
- Kept the assignment database Single-AZ and disabled paid performance insights
  and enhanced monitoring; this is not presented as production availability.
- Ran recursive Terraform formatting and validation successfully.

## Entry 8 - Terraform S3 Storage Module

**Date:** 2026-06-19

**Tool:** OpenAI Codex

**Exact prompt:**

> # Context from my IDE setup:
>
> ## Open tabs:
> - AI_USAGE_LOG.md: ssagnik/Ocean_Across_DevOps_Assignment/AI_USAGE_LOG.md
> - ADR-0001-security-first-aws-architecture.md: ssagnik/Ocean_Across_DevOps_Assignment/docs/decisions/ADR-0001-security-first-aws-architecture.md
>
> ## My request for Codex:
> Implement the Terraform storage module.
>
> Requirements:
> - One S3 bucket for payroll documents and reports.
> - Enable versioning.
> - Enable server-side encryption.
> - Block all public access.
> - Use prefixes for portal/domain boundaries:
>   - companies/
>   - bureaus/
>   - employees/
> - Create bucket policies or IAM policy documents showing that:
>   - company role can only access companies/*
>   - bureau role can only access bureaus/*
>   - employee role can only access employees/*
> - Do not allow wildcard access to the full bucket.
> - Add lifecycle policy examples if appropriate, but keep them simple.
> - Include comments explaining how S3 prefix isolation acts as a second boundary if application logic fails.

**Response or key output used:**

Implemented one versioned, SSE-S3 encrypted payroll-document bucket with
bucket-owner-enforced ownership and full public-access blocking. Added separate
Companies, Bureaus, and Employees inline IAM policies, explicit cross-prefix
bucket-policy denies, mandatory TLS, and a simple noncurrent-version and
multipart-upload lifecycle rule.

**Changes, adaptations, or rejections:**

- Used a generated bucket-name suffix to satisfy S3 global uniqueness without
  embedding account identifiers.
- Attached object permissions only to `<portal>/*`; no identity policy allows
  object access across the complete bucket namespace.
- Restricted bucket and version listing using `s3:prefix` conditions.
- Added explicit resource-policy denies for the other two portal prefixes so a
  future broad identity allow cannot silently collapse the boundary.
- Retained current object versions indefinitely and expired only noncurrent
  versions after the configured retention period.
- Omitted deployment artifacts from the payroll bucket because executable and
  sensitive document content should not share a trust boundary.
- Documented that this protects portal categories, not separate customers under
  `companies/`; tenant-specific keys and authorization remain necessary.
- Ran recursive Terraform formatting and validation successfully.

## Entry 9 - S3 Policy Security Review

**Date:** 2026-06-19

**Tool:** OpenAI Codex

**Exact prompt:**

> # Context from my IDE setup:
>
> ## Open tabs:
> - AI_USAGE_LOG.md: ssagnik/Ocean_Across_DevOps_Assignment/AI_USAGE_LOG.md
> - ADR-0001-security-first-aws-architecture.md: ssagnik/Ocean_Across_DevOps_Assignment/docs/decisions/ADR-0001-security-first-aws-architecture.md
>
> ## My request for Codex:
> Review the S3 policy you generated. Identify any statement that could accidentally allow cross-tenant access, list bucket-wide access, or public access. Then provide a corrected least-privilege policy.

**Response or key output used:**

Reviewed and corrected the generated identity and bucket policies. The original
policy had no public allow and conditioned bucket listing by prefix, but its
cross-prefix explicit deny covered only the current object action list. The
corrected resource policy denies each portal role from every object namespace
except its own, denies out-of-prefix listing, and denies bucket administration.

**Changes, adaptations, or rejections:**

- Identified that the original claim about surviving any future broad identity
  policy was too strong because omitted S3 object actions were not explicitly
  denied.
- Replaced enumeration of the other two prefixes with `NotResource` for the
  role's own prefix, which also protects unknown future object namespaces.
- Added an explicit bucket-administration deny for portal roles while retaining
  only prefix-conditioned list operations.
- Removed runtime access to old object versions and version listing because the
  placeholder application has no stated recovery requirement; version recovery
  belongs to an operational role.
- Confirmed that the wildcard principal and full object ARN in the TLS statement
  are part of an explicit deny and therefore grant no public access.
- Confirmed that all four S3 Block Public Access settings remain enabled.
- Retained the documented limitation that one Companies role can access all
  objects under `companies/`; customer-level isolation requires tenant-scoped
  credentials or trusted session tags and cannot be provided by this shared EC2
  role alone.

## Entry 10 - Terraform IAM Module

**Date:** 2026-06-19

**Tool:** OpenAI Codex

**Exact prompt:**

> # Context from my IDE setup:
>
> ## Open tabs:
> - AI_USAGE_LOG.md: ssagnik/Ocean_Across_DevOps_Assignment/AI_USAGE_LOG.md
> - ADR-0001-security-first-aws-architecture.md: ssagnik/Ocean_Across_DevOps_Assignment/docs/decisions/ADR-0001-security-first-aws-architecture.md
>
> ## My request for Codex:
> Implement the Terraform IAM module.
>
> Requirements:
> - Create separate IAM roles and instance profiles for:
>   - company portal EC2
>   - bureau portal EC2
>   - employee portal EC2
> - Each role should have least-privilege permissions.
> - Each role may only access its own S3 prefix.
> - Each role may only read the secrets/parameters required by its own service.
> - Include CloudWatch Logs permissions for application logging.
> - Include SSM permissions if using SSM-based deployment or Session Manager.
> - No administrator policies.
> - No broad s3:* on all resources.
> - No hardcoded credentials.
>
> Add comments explaining the security boundary created by IAM.

**Response or key output used:**

Completed the IAM module with separate Companies, Bureaus, and Employees EC2
roles and instance profiles. Added portal-specific S3 object/list permissions,
Parameter Store paths, CloudWatch Logs groups, minimal Session Manager channel
permissions, and the independent S3 bucket policy guardrails.

**Changes, adaptations, or rejections:**

- Moved the S3 identity and bucket policies from the storage module into IAM so
  permission ownership is centralized and module dependencies remain acyclic.
- Scoped S3 allows to each portal prefix; broad `s3:*` appears only in explicit
  deny statements and never grants access.
- Scoped Parameter Store reads to
  `/payroll/<environment>/<portal>/*`; no role can read the RDS master secret.
- Scoped CloudWatch log writes to
  `/ocean-across/<environment>/<portal>` and omitted log-group administration.
- Rejected `AmazonSSMManagedInstanceCore` after review because its current AWS
  policy includes `ssm:GetParameter` and `ssm:GetParameters` on `Resource: "*"`,
  which would bypass portal parameter isolation.
- Replaced it with AWS's documented minimal Session Manager actions:
  `ssm:UpdateInstanceInformation` plus the four `ssmmessages` channel actions,
  and the six `ec2messages` transport operations needed for SSM Run Command in
  the selected region. Their wildcard resource is a service limitation and
  grants no parameter, secret, or application-data access.
- Added no administrator, IAM mutation, full-bucket S3 allow, static credential,
  or plaintext secret permissions.
- Retained the limitation that these roles isolate portal categories, not
  individual customers sharing one portal role.
- Ran recursive Terraform formatting and validation successfully.
- I accepted the modular Terraform structure because it makes the infrastructure easier to review. I rejected overly complex module abstractions because the assignment values clarity and explanation over production-scale complexity.

## Entry 11 - Dockerized Placeholder Backend

**Date:** 2026-06-19

**Tool:** OpenAI Codex

**Exact prompt:**

> # Context from my IDE setup:
>
> ## Open tabs:
> - AI_USAGE_LOG.md: ssagnik/Ocean_Across_DevOps_Assignment/AI_USAGE_LOG.md
> - ADR-0001-security-first-aws-architecture.md: ssagnik/Ocean_Across_DevOps_Assignment/docs/decisions/ADR-0001-security-first-aws-architecture.md
>
> ## My request for Codex:
> Create a simple Dockerized placeholder backend application for the assignment.
>
> Requirements:
> - Use a minimal Node.js or Python app.
> - Expose a health endpoint at /health.
> - Expose an endpoint that returns the portal type from an environment variable.
> - Do not include real payroll logic.
> - Include:
>   - app source file
>   - Dockerfile
>   - .dockerignore
>   - simple unit test
> - The app should be suitable for CI/CD demonstration.
>
> The purpose is to test build, test, and deployment flow, not to implement business functionality.

**Response or key output used:**

Created a dependency-free Python placeholder backend with `/health` and
`/portal` JSON endpoints, a non-root Alpine-based Docker image, Docker health
check, focused build context, and standard-library unit tests.

**Changes, adaptations, or rejections:**

- Chose the Python standard library instead of a web framework so CI unit tests
  require no package installation or lockfile maintenance.
- Read `PORTAL_TYPE` at request time and return `unknown` when it is missing or
  blank; no tenant, payroll, PII, or banking logic was added.
- Added basic no-cache and content-type security headers.
- Configured the container to run as a non-root user and included a Docker-native
  health check against `/health`.
- Excluded tests, local environments, bytecode, and coverage artifacts from the
  runtime image context.
- Added Python-generated artifacts to the repository `.gitignore`.
- Ran four unit tests, Python bytecode compilation, and live HTTP checks for
  `/health` and `/portal`; all passed.
- Attempted the Docker build both normally and with elevated execution, but the
  host denied access to `/var/run/docker.sock`, so the image build was not
  verified in this environment.

## Entry 12 - GitHub Actions CI/CD Workflow

**Date:** 2026-06-19

**Tool:** OpenAI Codex

**Exact prompt:**

> # Context from my IDE setup:
>
> ## Open tabs:
> - AI_USAGE_LOG.md: ssagnik/Ocean_Across_DevOps_Assignment/AI_USAGE_LOG.md
> - ADR-0001-security-first-aws-architecture.md: ssagnik/Ocean_Across_DevOps_Assignment/docs/decisions/ADR-0001-security-first-aws-architecture.md
>
> ## My request for Codex:
> Create a GitHub Actions workflow for this repository.
>
> Requirements:
> - Runs on push to main.
> - Also supports manual workflow_dispatch.
> - Builds and tests a simple Dockerized application.
> - Deploys to EC2 using AWS Systems Manager where possible.
> - Do not use a paid container registry.
> - Do not expose secrets in the YAML.
> - Use GitHub Actions secrets or environment variables for AWS credentials and deployment targets.
> - Support independent deployment by team/service:
>   - frontend
>   - backend
>   - ai
> - Allow selecting target environment:
>   - dev
>   - production
> - Make the workflow clear enough for an evaluator to understand.
>
> Include comments explaining:
> - where secrets are stored
> - how environment-specific config is selected
> - how teams can deploy independently without interfering with each other

**Response or key output used:**

Created a two-job GitHub Actions workflow that tests and builds the placeholder
application, transfers the tested image without a paid container registry, and
deploys an independently selected service to EC2 through SSM Run Command.

**Changes, adaptations, or rejections:**

- A push to `main` deploys the backend to `dev`; manual runs select frontend,
  backend, or AI and either the dev or production GitHub Environment.
- Used GitHub OIDC to obtain short-lived AWS credentials instead of storing
  long-lived AWS access keys in GitHub or the workflow.
- Used GitHub's temporary artifact storage between jobs and a private,
  environment-configured S3 deployment bucket to transport the Docker image;
  the payroll document bucket must not be reused for deployment artifacts.
- Added a SHA-256 integrity check before loading the image on EC2.
- Scoped concurrency by service and environment so different teams deploy
  independently while overlapping deployments to the same target are serialized.
- Kept AWS role ARN, region, deployment bucket, and service instance IDs in
  GitHub Environment variables. Runtime application secrets remain in AWS SSM
  Parameter Store or Secrets Manager and are not passed through CI/CD.
- Production review approval is delegated to GitHub Environment protection.
- Live SSM deployment requires a separately provisioned least-privilege GitHub
  OIDC role, encrypted deployment bucket, S3 artifact read permissions on each
  selected EC2 role, and private SSM/S3 connectivity or controlled egress.

## Entry 13 - GitHub Actions Security Audit and Hardening

**Date:** 2026-06-19

**Tool:** OpenAI Codex

**Exact prompt:**

> # Context from my IDE setup:
>
> ## Open tabs:
> - AI_USAGE_LOG.md: ssagnik/Ocean_Across_DevOps_Assignment/AI_USAGE_LOG.md
> - ADR-0001-security-first-aws-architecture.md: ssagnik/Ocean_Across_DevOps_Assignment/docs/decisions/ADR-0001-security-first-aws-architecture.md
>
> ## My request for Codex:
> Audit this GitHub Actions workflow for secret exposure, unsafe shell commands, overly broad AWS permissions, and accidental production deployment risk. Then provide a hardened version.

**Response or key output used:**

Audited the workflow and replaced it with a fail-closed version that pins action
SHAs, separates service deployment roles, caps each AWS session, verifies the
target and artifact, and adds explicit production and container rollout guards.

**Changes, adaptations, or rejections:**

- Identified mutable action tags, one shared AWS deployment role, unverified EC2
  targets, optional-only production gates, paired artifact/checksum trust, and
  remote log output as the main workflow risks.
- Pinned every external action to a resolved full commit SHA and disabled
  checkout credential persistence.
- Added separate frontend, backend, and AI role variables plus a per-run inline
  session policy limited to one artifact prefix, one SSM document, and one
  tagged instance. The base role must still enforce least privilege.
- Added manual-only production deployment from protected `main`, exact workflow
  ref and typed confirmation checks, an explicit production enable variable,
  and documented required GitHub Environment protections.
- Added AWS account, region, EC2 tag, running-state, and SSM-online validation.
- Reverified the image digest between jobs, used immutable SSE-S3 uploads with
  checksum metadata, and passed the expected digest separately to the host.
- Rebuilt the remote command using a quoted heredoc, validated positional
  arguments, and shell-escaped command values instead of interpolating them.
- Removed application and remote command output from GitHub logs.
- Added restricted Docker flags, candidate health checking, and best-effort
  rollback before replacing the active service.
- Documented that `AWS-RunShellScript` remains root-equivalent, the deployment
  IAM roles and artifact bucket are not yet provisioned by Terraform, the base
  image is not digest-pinned or signed, private endpoint connectivity is absent,
  and frontend/backend/AI targets do not directly match the current
  Companies/Bureaus/Employees compute model.
- Clarified that separate roles and concurrency provide operational independence,
  not per-team GitHub authorization; strong team separation needs service-specific
  environments or reusable workflows with distinct approval and OIDC boundaries.

## Entry 14 - Terraform Monitoring Module

**Date:** 2026-06-19

**Tool:** OpenAI Codex

**Exact prompt:**

> # Context from my IDE setup:
>
> ## Open tabs:
> - AI_USAGE_LOG.md: ssagnik/Ocean_Across_DevOps_Assignment/AI_USAGE_LOG.md
> - ADR-0001-security-first-aws-architecture.md: ssagnik/Ocean_Across_DevOps_Assignment/docs/decisions/ADR-0001-security-first-aws-architecture.md
>
> ## My request for Codex:
> Implement the Terraform monitoring module.
>
> Requirements:
> - CloudWatch log groups for each portal service:
>   - company
>   - bureau
>   - employee
> - Sensible retention policy, configurable by variable.
> - CloudWatch alarm for EC2 CPU utilization.
> - CloudWatch alarm for RDS database connection threshold.
> - SNS topic for critical alerts.
> - Email subscription should be configurable, not hardcoded.
> - Add outputs for alarm names and SNS topic ARN.
>
> Explain in comments how these alarms support incident readiness.

**Response or key output used:**

Implemented portal-specific CloudWatch log groups, EC2 CPU and RDS connection
alarms, a restricted SNS critical-alert topic, and an optional confirmed email
subscription with root and module outputs.

**Changes, adaptations, or rejections:**

- Used the repository's canonical `companies`, `bureaus`, and `employees` keys
  so log group names remain compatible with the existing portal IAM policies.
- Added finite, validated CloudWatch retention with a 30-day example value.
- Created one sustained high-CPU alarm per portal instance and one RDS database
  connection alarm; both thresholds are configurable and default to 80.
- Routed alarm and recovery state changes to SNS and restricted CloudWatch
  publishing to alarms from the same AWS account using `SourceAccount` and
  `SourceArn` conditions.
- Rejected `alias/aws/sns` for this integration because AWS requires a
  customer-managed key policy to authorize CloudWatch as an encrypted-topic
  event source. Encryption is therefore an optional CMK ARN rather than a
  configuration that appears secure but silently blocks alarm delivery.
- Made the email endpoint nullable and externally configurable. No subscription
  is created when it is null, and AWS confirmation is required before delivery.
- Added comments connecting sustained CPU pressure and connection exhaustion to
  incident detection, investigation, containment, and recovery readiness.
- Exposed portal log group names, per-portal CPU alarms, the RDS alarm, the full
  alarm list, and the critical SNS topic ARN from the module and root stack.

## Entry 15 - README Multi-Tenancy Architecture

**Date:** 2026-06-19

**Tool:** OpenAI Codex

**Exact prompt:**

> # Context from my IDE setup:
>
> ## Open tabs:
> - AI_USAGE_LOG.md: ssagnik/Ocean_Across_DevOps_Assignment/AI_USAGE_LOG.md
> - ADR-0001-security-first-aws-architecture.md: ssagnik/Ocean_Across_DevOps_Assignment/docs/decisions/ADR-0001-security-first-aws-architecture.md
>
> ## My request for Codex:
> Write the multi-tenancy architecture section for the README.
>
> The platform has:
> - Companies
> - Bureaus
> - Employees
>
> Requirements:
> 1. Choose and justify a tenancy model.
> 2. Explain how tenant context is established at login.
> 3. Explain how tenant context is propagated through API requests.
> 4. Show an example of a safe tenant-scoped query.
> 5. Explain how PostgreSQL Row-Level Security can prevent cross-tenant leakage.
> 6. Explain how IAM roles and S3 prefixes create infrastructure-level boundaries.
> 7. Describe onboarding for a new Company or Bureau.
> 8. Describe offboarding, including data deletion, access revocation, and audit trail.
>
> Use a security-first tone. Include trade-offs.

**Response or key output used:**

Created a root README with a security-first multi-tenancy architecture covering
the pooled data model, verified request context, PostgreSQL RLS, AWS boundaries,
tenant lifecycle processes, and production trade-offs.

**Changes, adaptations, or rejections:**

- Defined Company as the primary payroll data tenant, Bureau as a delegated
  tenant acting only for assigned Companies, and Employee as a Company-scoped
  identity restricted to its own permitted records.
- Selected a pooled PostgreSQL database and shared schema with immutable tenant
  keys because it fits the assignment's single micro RDS constraint.
- Derived tenant context from verified memberships at login, propagated only
  signed and server-validated context, and rejected client tenant headers as
  authorization evidence.
- Added a parameterized transaction example that uses explicit tenant predicates
  and transaction-local PostgreSQL context on the same pooled connection.
- Added an RLS policy using default-deny context, `USING`, `WITH CHECK`, forced
  RLS, and non-owner runtime roles, plus its SQL-injection limitation.
- Distinguished portal-level IAM/S3 isolation from customer-level isolation;
  nested tenant prefixes do not narrow the current shared portal instance role.
- Documented Company and Bureau onboarding with deny-by-default assignments,
  MFA, immutable IDs, server-generated object keys, and negative tests.
- Separated immediate access revocation from legally scheduled deletion, including
  S3 versions, RDS backups, downstream recipients, and a minimal audit trail.
- Used current official PostgreSQL, GOV.UK, and ICO guidance for RLS, PAYE record
  retention, storage limitation, and the non-absolute right to erasure.

## Entry 16 - Unsafe and Safe Tenant Query Examples

**Date:** 2026-06-19

**Tool:** OpenAI Codex

**Exact prompt:**

> # Context from my IDE setup:
>
> ## Open tabs:
> - AI_USAGE_LOG.md: ssagnik/Ocean_Across_DevOps_Assignment/AI_USAGE_LOG.md
> - ADR-0001-security-first-aws-architecture.md: ssagnik/Ocean_Across_DevOps_Assignment/docs/decisions/ADR-0001-security-first-aws-architecture.md
>
> ## My request for Codex:
> Add an example unsafe query and then show the corrected safe version using tenant_id and PostgreSQL Row-Level Security. Explain why relying only on application WHERE clauses is not sufficient for payroll data.

**Response or key output used:**

Expanded the README with a parameterized but tenant-unsafe payroll query, a
corrected transaction-scoped `tenant_id` query, and the corresponding forced RLS
policy.

**Changes, adaptations, or rejections:**

- Deliberately made the unsafe query parameterized to show that preventing SQL
  injection does not establish tenant authorization when `tenant_id` is absent.
- Defined `tenant_id` as the immutable Company UUID used to partition payroll
  rows, while allowing domain-facing code to refer to the same value as
  `company_id`.
- Corrected the safe query to set transaction-local RLS context and apply an
  explicit `tenant_id` predicate on the same pooled database connection.
- Updated both `USING` and `WITH CHECK` RLS expressions to enforce `tenant_id` on
  reads, writes, updates, and deletes.
- Explained that missed predicates, incorrect joins or Boolean logic, background
  jobs, bulk exports, and write paths make application-only isolation inadequate
  for payroll and bank data.
- Retained the limitation that RLS does not replace parameterized SQL,
  least-privilege non-owner roles, or negative cross-tenant testing.

## Entry 17 - Public RDS Incident Response Runbook

**Date:** 2026-06-19

**Tool:** OpenAI Codex

**Exact prompt:**

> Write a one-page incident response runbook for this scenario:
>
> An RDS PostgreSQL database containing payroll data was accidentally made publicly accessible.
>
> The runbook should include:
> 1. Detection signals.
> 2. Immediate containment steps.
> 3. Investigation steps.
> 4. Evidence preservation.
> 5. Recovery steps.
> 6. Customer/compliance communication considerations.
> 7. Preventive actions.
> 8. AWS-native controls that would reduce recurrence.
>
> Keep it practical and suitable for inclusion in a DevOps assignment README.

**Response or key output used:**

Added a practical README runbook for accidental public exposure of the payroll
RDS PostgreSQL instance, from detection and containment through recovery,
communications, and recurrence prevention.

**Changes, adaptations, or rejections:**

- Classified the event as SEV-1 until effective reachability and unauthorized
  access are disproved, and assigned incident, cloud, database, and DPO roles.
- Prioritized removal of public security-group ingress before disabling RDS
  public accessibility because security groups control effective connectivity.
- Preserved volatile sessions, logs, configuration history, and an encrypted
  snapshot before destructive cleanup, with hashing and chain of custody.
- Required investigation of both exposure and actual access, including
  CloudTrail, AWS Config, database logs, metrics, VPC Flow Logs, GuardDuty,
  database changes, and affected tenant/data scope.
- Used restoration to a new private instance when integrity is uncertain, with
  credential rotation, RLS testing, reconciliation, and monitored re-entry.
- Included controller/processor communications, the risk-based ICO threshold,
  the feasible 72-hour reporting window, high-risk individual notification, and
  mandatory recording of the decision.
- Added IaC review, policy-as-code, restricted mutation permissions, recovery
  tests, AWS Config, Security Hub RDS.2, CloudTrail/EventBridge, GuardDuty RDS
  Protection, private networking, secrets rotation, and backup controls.
- Avoided claiming that absent logs prove no access or that public accessibility
  alone proves effective internet reachability.

## Entry 18 - Incident Runbook Control Clarifications

**Date:** 2026-06-19

**Tool:** OpenAI Codex

**Exact prompt:**

> Mention AWS Config, CloudTrail, VPC Flow Logs, Security Group review, RDS public accessibility flag, credential rotation, snapshot review, and post-incident lessons learned.

**Response or key output used:**

Updated the incident runbook so every requested detection, containment,
investigation, recovery, and learning control is directly identifiable.

**Changes, adaptations, or rejections:**

- Retained the existing AWS Config, CloudTrail, VPC Flow Logs,
  `PubliclyAccessible` flag, credential rotation, Security Hub, and GuardDuty
  guidance.
- Relabelled containment as an explicit Security Group review before removing
  public PostgreSQL ingress.
- Added review of automated and manual snapshots, sharing attributes, copies,
  exports, restore events, encryption, and unintended recipients.
- Made the post-incident lessons-learned review explicit, including root cause,
  control failures, effective responses, owners, deadlines, and document/test
  updates.

## Entry 19 - UK GDPR Compliance README Section

**Date:** 2026-06-19

**Tool:** OpenAI Codex

**Exact prompt:**

> Write the UK compliance section for the README.
>
> Answer these questions:
> 1. What AWS-native controls would help stay compliant with UK GDPR when storing employee PII and bank data?
> 2. How would we ensure data residency within the UK/EU region?
> 3. How would we handle an employee right-to-erasure request across all services?
>
> Use this context:
> - Payroll platform
> - UK market
> - Employee PII and bank details
> - AWS infrastructure
> - RDS PostgreSQL
> - S3
> - IAM
> - CloudWatch
> - Secrets Manager or SSM Parameter Store
>
> Be specific and practical. Avoid claiming that AWS services alone guarantee GDPR compliance.

**Response or key output used:**

Added a practical UK GDPR README section covering AWS technical controls,
enforceable UK-region residency, and a verified cross-service employee erasure
workflow without treating AWS service use as proof of compliance.

**Changes, adaptations, or rejections:**

- Separated controls already implemented by the assignment from production
  additions such as CloudTrail, Config, Security Hub, GuardDuty, Macie, Access
  Analyzer, organization policies, customer-managed keys, and immutable logging.
- Applied AWS shared responsibility explicitly: AWS secures its infrastructure,
  while the platform/controller remains responsible for lawful processing,
  DPIAs, contracts, retention, access, incidents, and data subject rights.
- Selected `eu-west-2` as the primary boundary and added regional Terraform
  state, SCP/Control Tower enforcement, cross-region replication restrictions,
  continuous inventory, and non-AWS data-path review.
- Avoided conflating UK and EU jurisdiction or claiming that a region selection
  covers global services, support access, subprocessors, exports, or DR transfers.
- Defined erasure intake, identity/controller verification, legal-basis review,
  dual-approved execution, independent verification, response, and minimal audit.
- Added service-specific handling for RDS, every S3 version and delete marker,
  EC2/application caches and exports, CloudWatch/SNS, Secrets Manager/SSM,
  IAM/application sessions, backups, snapshots, Bureaus, and downstream copies.
- Distinguished immediate access restriction and live-system deletion from PAYE
  retention and ICO “beyond use” treatment for backups that cannot be edited.
- Used current official AWS, ICO, and GOV.UK sources and noted that ICO erasure
  guidance is under review following the Data (Use and Access) Act 2025.

## Entry 20 - Mermaid AWS Architecture Diagram

**Date:** 2026-06-19

**Tool:** OpenAI Codex

**Exact prompt:**

> Create a Mermaid architecture diagram for this AWS payroll platform.
>
> Include:
> - Users accessing three portals:
>   - Company Portal
>   - Bureau Portal
>   - Employee Portal
> - VPC across two Availability Zones
> - Public subnets
> - Private subnets
> - Three isolated EC2 instances
> - RDS PostgreSQL in private subnet
> - S3 bucket with tenant prefixes
> - IAM roles per portal
> - Secrets Manager or SSM Parameter Store
> - CloudWatch Logs and Alarms
> - SNS alerts
> - GitHub Actions deploying through SSM
>
> Show security boundaries clearly:
> - public vs private subnets
> - tenant/portal compute isolation
> - database private access
> - S3 prefix access boundaries
>
> Generate Mermaid syntax suitable for README.md.

**Response or key output used:**

Added a Mermaid flowchart to the README showing the two-AZ VPC, isolated portal
compute, private database tier, managed AWS services, monitoring, and intended
OIDC/SSM deployment flow.

**Changes, adaptations, or rejections:**

- Represented public, private application, and private database tiers as distinct
  styled security boundaries inside the VPC.
- Placed Bureaus and Employees application subnets in one logical AZ and the
  Companies subnet in the other, matching the module's deterministic sorted-key
  distribution while keeping the AZ names account-independent.
- Showed a two-AZ RDS subnet group but labelled the assignment database as a
  Single-AZ private instance with `PubliclyAccessible = false` and SG-only access.
- Drew separate subnet/NACL/security-group boundaries around all three EC2
  instances and allowed only their named security groups to PostgreSQL over TLS.
- Mapped each EC2 role to only its own S3 top-level prefix and SSM parameter path,
  while showing the finer tenant key convention inside each prefix.
- Kept the RDS master secret separate from portal runtime parameter access.
- Added per-portal CloudWatch logs/CPU alarms, the RDS connection alarm, and SNS.
- Included GitHub OIDC, service deployment roles, a separate artifact bucket,
  and SSM Run Command without implying that executable content shares the payroll
  document bucket.
- Used dashed arrows and an explanatory note for the unprovisioned ingress tier
  and live SSM/S3 path, which still requires VPC endpoints or controlled egress.

## Entry 21 - Complete Assignment README

**Date:** 2026-06-19

**Tool:** OpenAI Codex

**Exact prompt:**

> Assemble a complete README.md for this assignment.
>
> The README should include:
> 1. Project overview.
> 2. Threat/security context.
> 3. Architecture summary.
> 4. Repository structure.
> 5. Terraform setup instructions.
> 6. CI/CD setup instructions.
> 7. Multi-tenancy design.
> 8. Security controls.
> 9. Monitoring and incident readiness.
> 10. UK GDPR compliance considerations.
> 11. Trade-offs and production improvements.
> 12. Cleanup instructions for AWS resources.
> 13. Notes that live deployment is optional and this repository focuses on well-structured IaC.
>
> Use a professional DevOps engineering tone.
>
> Do not claim resources were deployed unless there is evidence.

**Response or key output used:**

Consolidated the repository's architecture, operations, security, compliance,
setup, and cleanup material into an evaluator-ready README grounded in the
implemented files and documented limitations.

**Changes, adaptations, or rejections:**

- Added a deployment-status statement that distinguishes implemented IaC from
  evidence of live AWS resources.
- Added the payroll threat context, security objectives, architecture summary,
  contents list, and repository map.
- Documented Terraform prerequisites, short-lived AWS authentication, validation,
  planning, optional apply, sensitive outputs, and production state handling.
- Documented the hardened GitHub Actions flow, required GitHub Environment
  variables and OIDC controls, local application checks, and production gates.
- Explicitly recorded missing live dependencies: artifact infrastructure, VPC
  endpoints/egress, package access, log forwarding, deployment roles, and the
  service-to-portal target-model mismatch.
- Added a consolidated security-control matrix and monitoring readiness section
  without treating source code as evidence of operating controls.
- Preserved and integrated the existing multi-tenancy/RLS, incident-response,
  and UK GDPR guidance.
- Added a trade-off matrix covering cost, availability, isolation, key
  management, deployment, telemetry, state, and AWS account boundaries.
- Added guarded cleanup instructions for versioned S3 data, RDS deletion
  protection and snapshots, Terraform destroy plans, out-of-band resources,
  legal holds, and post-destroy verification.

## Entry 22 - Repository Security and DevOps Review

**Date:** 2026-06-19

**Tool:** OpenAI Codex

**Exact prompt:**

> Perform a security and DevOps review of the repository.
>
> Check for:
> - hardcoded secrets
> - overly broad IAM permissions
> - public RDS exposure
> - public S3 access
> - missing encryption
> - missing private subnet placement
> - weak security group rules
> - missing CloudWatch logs or alarms
> - CI/CD secret exposure
> - unclear tenant isolation
> - README claims that are not supported by code
> - use of services outside the assignment’s free-tier-safe list
>
> Return:
> 1. Issues found.
> 2. Severity.
> 3. Recommended fix.
> 4. Exact file to modify.
> 5. Corrected code snippets where needed.

**Response or key output used:**

Performed a static security and DevOps review of the Terraform modules, GitHub
Actions workflow, placeholder application, Docker image, documentation, and
repository artefacts. Reported findings by severity with exact remediation
targets and representative corrected snippets.

**Changes, adaptations, or rejections:**

- Confirmed no hardcoded credentials, private keys, Terraform state, local
  variable files, or environment files were present in the reviewed tree.
- Distinguished broad explicit Deny statements and service APIs that require
  wildcard resources from overly broad Allow permissions.
- Verified RDS private placement and public-access flag, S3 Block Public Access,
  portal-scoped security groups, private EC2 placement, and baseline data
  encryption in code.
- Identified implementation gaps for RLS/runtime database roles, private AWS API
  connectivity, deployment OIDC roles/artifact permissions, log delivery, and
  service/portal deployment targeting.
- Identified the root-equivalent managed SSM document, unpinned container base,
  absent Terraform validation/scanning in CI, and local-state limitations.
- Identified the optional SNS KMS configuration and output descriptions that
  incorrectly call the topic encrypted when no key is supplied.
- Compared README baseline statements with implemented code and separated
  documented production recommendations from resources actually provisioned.
- Confirmed provisioned AWS resources remain within the assignment service set;
  KMS and other production services appear only as optional integration or
  documented recommendations.
- Ran all four Python unit tests successfully and parsed the GitHub Actions YAML;
  Terraform and dedicated security scanners were unavailable in the environment.

## Entry 23 - Structured AI Interaction Log

**Date:** 2026-06-19

**Tool:** OpenAI Codex

**Exact prompt:**

> Create an ai_log.md file for this assignment.
>
> Use the following structure for each AI interaction:
> - Prompt number
> - Exact prompt used
> - Summary of AI output
> - What I accepted
> - What I changed
> - What I rejected
> - Why the change or rejection was necessary
>
> Use a transparent tone. Make it clear that I used AI as an assistant, but I reviewed and adapted the output for security, cost, and assignment fit.
>
> Do not invent prompts I did not use. Use placeholders where I need to paste my real prompts.

**Response or key output used:**

The response generated a second interaction log from the 22 prompts already in
this file and added explicit author-review placeholders where personal decisions
could not be established from repository history.

**Changes, adaptations, or rejections:**

- Retained the requirement to record exact prompts, key output, and reviewed
  changes or rejections for every interaction.
- Rejected the generated duplicate before submission because unresolved
  placeholders made it incomplete and two overlapping logs obscured which one
  was authoritative.
- Kept this existing complete record as the single source of truth and appended
  the later interactions here.

## Entry 24 - Strict Review and Corrected Version

**Date:** 2026-06-19

**Tool:** OpenAI Codex

**Exact prompt:**

> Review your all previous answers as a strict DevOps security reviewer.
>
> Do not praise the solution.
>
> Find weaknesses, unsafe defaults, missing assignment requirements, unnecessary cost, and places where the README might overclaim.
>
> Then provide a corrected version.

**Response or key output used:**

The response re-audited the assignment brief, Terraform, workflow, application,
ADR, security audit, README, and AI log. It corrected deployment defaults,
replaced arbitrary SSM shell content with a validated account-owned document and
fixed host script, added Terraform CI validation and infrastructure log groups,
made missing metrics alert, removed optional KMS from the cost-constrained
baseline, and rewrote unsupported implementation claims as explicit design
gaps.

**Changes, adaptations, or rejections:**

- Retained the fail-closed manual deployment default, exact target validation,
  account-owned SSM document, digest checks, and protected production gates.
- Retained Terraform validation, infrastructure log groups, missing-data alarm
  behavior, and documentation that separates intended architecture from live
  proof.
- Retained the assignment-safe encryption baseline and documented customer-
  managed KMS keys only as a production improvement because KMS was outside the
  assignment's stated safe-service list.
- Did not claim that external OIDC roles, an artifact bucket, VPC endpoints,
  runtime RLS roles, log shipping, or frontend/AI hosts were provisioned.

## Entry 25 - Submission Completeness Review

**Date:** 2026-06-19

**Tool:** OpenAI Codex

**Exact prompt:**

> Prompt- Email- Assignment for the role of DevOps Engineer at Ocean Across
>
> Hi Sagnik
>
> This email pertains to your application for the DevOps Engineer position at Ocean Across. As part of the selection process, please find the attached assignment, which we request you complete and submit within the next 48 hours.
>
> Kindly include the complete prompt log used to generate the code.
>
> Please do not hesitate to contact us if you have any questions regarding this matter.
>
> My repo link- https://github.com/sagniksalui/Ocean_Across_DevOps_Assignment
>
> Check my repo based on the mail and the attachment and tell me what else is missing from my repo based on the ask and also draft the reply mail for me.

**Response or key output used:**

The review compared the public repository with the assignment and found the
core Terraform, placeholder app, CI/CD, README, runbook, and compliance content
present. It identified two submission blockers: the duplicate `ai_log.md`
contained unresolved placeholders, and the architecture existed only as Mermaid
source rather than the requested standalone image or PDF. It also recommended a
clear note about the workflow service names and Terraform portal hosts and
provided a draft submission email.

**Changes, adaptations, or rejections:**

- Accepted the two concrete submission gaps after confirming them against the
  local assignment PDF and repository.
- Accepted the recommendation to clarify the service-to-portal deployment model.
- Rejected any implication that a successful workflow proves a live AWS
  deployment; the README continues to state the external dependencies and
  disabled deployment default.
- Adapted the email to retain the explicit statement that no live AWS resources
  were provisioned.

## Entry 26 - Implement Submission Fixes

**Date:** 2026-06-19

**Tool:** OpenAI Codex

**Exact prompt:**

> Implement the fixes based on my prompt and answer to the prompt.
>
> Prompt- Email- Assignment for the role of DevOps Engineer at Ocean Across
>
> Hi Sagnik
>
> This email pertains to your application for the DevOps Engineer position at Ocean Across. As part of the selection process, please find the attached assignment, which we request you complete and submit within the next 48 hours.
>
> Kindly include the complete prompt log used to generate the code.
>
> Please do not hesitate to contact us if you have any questions regarding this matter.
>
> My repo link- https://github.com/sagniksalui/Ocean_Across_DevOps_Assignment
>
> Check my repo based on the mail and the attachment and tell me what else is missing from my repo based on the ask and also draft the reply mail for me.

**Response or key output used:**

The response inspected the assignment PDF, prior completeness review, local Git
state, README, workflow, Terraform, and both AI logs. It implemented the missing
standalone diagram and documentation corrections, consolidated the prompt log,
and ran focused repository validation.

**Changes, adaptations, or rejections:**

- Added `docs/architecture.svg`, rendered a reviewer-friendly
  `docs/architecture.png`, and linked both from the architecture section while
  retaining Mermaid as reviewable source.
- Removed the incomplete duplicate `ai_log.md` and made this complete log the
  only authoritative AI record.
- Updated README deliverable status and repository structure so neither claims
  that author placeholders remain.
- Added an explicit service/portal target table: `frontend`, `backend`, and `ai`
  are workflow service categories, while `companies`, `bureaus`, and `employees`
  are Terraform portal hosts.
- Preserved fail-closed deployment limitations rather than inventing resources
  or mappings that the Terraform does not create.
