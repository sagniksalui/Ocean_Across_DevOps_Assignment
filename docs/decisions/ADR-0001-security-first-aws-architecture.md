# ADR-0001: Security-First AWS Architecture Within Assignment Constraints

- **Status:** Proposed
- **Date:** 2026-06-19
- **Last amended:** 2026-06-19 (implementation-status corrections)
- **Decision owners:** DevOps and application security
- **Scope:** Assignment reference architecture; not a production approval

## Context

The platform processes UK payroll data, including employee PII, bank details,
payroll records, and employer information. It exposes separate Companies,
Bureaus, and Employees portals. A failure in one portal must not grant access to
another portal's compute, AWS resources, or data.

The assignment requires one EC2 instance per portal type, PostgreSQL on RDS, S3,
IAM boundaries, network isolation, monitoring, and SSM-based or SSH-based
deployment. Live deployment is optional. If deployed for the assignment, the
design must remain within the stated free-tier-friendly service set: VPC, EC2,
RDS, S3, IAM, CloudWatch, SNS, and SSM Parameter Store or Secrets Manager.

"Tenant type" in the assignment means portal type. It must not be confused with
an actual customer tenant. A Companies EC2 role can isolate Companies resources
from Bureaus resources, but it cannot by itself isolate Company A from Company B.
Customer-level isolation therefore also requires database policies and
application authorization.

AWS Free Tier is a billing allowance rather than a security architecture.
Eligibility, regional availability, and current quotas must be checked before
any `terraform apply`.

## Decision Drivers

- Keep payroll data and backups in the selected UK region.
- Prevent public database access and cross-portal network access.
- Apply least privilege independently to each portal.
- Provide defense in depth if application authorization fails.
- Avoid long-lived AWS and host credentials in GitHub.
- Produce valid, reviewable IaC without requiring a live AWS deployment.
- Use only the assignment's allowed AWS services in the assessment design.

## Decision

### 1. Region and Data Residency

All regional resources will be created in `eu-west-2` (London). RDS snapshots,
S3 objects, SSM parameters, CloudWatch logs, and deployment artifacts will stay
in that region. Cross-region S3 replication and cross-region RDS snapshots will
be disabled.

London best supports the stated UK residency goal and reduces latency for UK
users. Region selection alone does not establish UK GDPR compliance: contracts,
data mapping, retention, access governance, subprocessors, and international
support-access controls remain necessary.

**Trade-off:** A single region avoids unapproved transfers but provides less
disaster resilience. Production needs a documented UK/EU disaster-recovery
region and a lawful transfer assessment before copying personal data there.

### 2. VPC Design

Use one dedicated `/16` VPC with DNS resolution and DNS hostnames enabled. Use
two Availability Zones and non-overlapping subnet groups:

- Two public subnets, one in each AZ, reserved for a future load balancer or
  controlled access tier.
- One private application subnet per portal, distributed across both AZs.
- Two private database subnets, one in each AZ, forming the RDS subnet group.
- An internet gateway and a public route table used only by public subnets.
- Separate application and database route tables with no internet default route.
- No VPC peering, transit routing, or cross-portal route.

Only one EC2 instance per portal is required, so each portal is placed in one AZ
while the workload as a whole spans two AZs. This does not make an individual
portal highly available.

**Trade-off:** More subnets and NACLs create additional configuration, but they
make portal trust boundaries visible and testable. Production should normally
use separate application subnets and may use separate AWS accounts or VPCs for
stronger blast-radius control.

### 3. Public and Private Subnet Strategy

EC2 instances run in portal-specific private application subnets. RDS runs only
in the separate private database subnets with `publicly_accessible = false`.
Neither private tier has a route to an internet gateway, automatic public IP
assignment, or a NAT gateway.

Public subnets are empty placeholders for a future load balancer or controlled
access component. Public IP assignment remains opt-in even in those subnets so
an accidentally placed instance is not automatically exposed.

**Trade-off:** This is the strongest no-cost routing posture but private EC2
instances cannot currently reach SSM, S3, CloudWatch public endpoints, package
repositories, or GitHub. A live SSM deployment is therefore not functional in
this assessment topology. Production should add interface endpoints for SSM and
CloudWatch, an S3 gateway endpoint, and an ALB with ACM/WAF; tightly controlled
NAT is an alternative where endpoint-only egress is insufficient.

### 4. Compute Isolation Per Portal Type

Companies, Bureaus, and Employees will each have a separate private EC2 instance,
instance profile, security group, application subnet/NACL, SSM parameter path,
CloudWatch application/infrastructure log groups, and S3 prefix. The repository
does not map the workflow's Frontend/Backend/AI targets to these portal hosts.
Instances are tagged with `Portal`, `Environment`, `DataClassification`, and
`ManagedBy`.

Instances use Amazon Linux 2023, encrypted gp3 root volumes, required IMDSv2,
no public IP, and no SSH key pair. User data contains no secrets and prepares a
portal-specific application directory before installing Docker. The AMI can be
pinned for reproducibility; null selects the newest matching Amazon-owned AL2023
x86_64 image during planning.

This prevents a compromised Employees process from automatically inheriting a
Companies role or filesystem and limits deployment and operational mistakes to
one portal. It also lets teams deploy each portal independently.

**Trade-off:** Three micro instances consume more allowance and operational
effort than one shared host, but sharing a host would contradict the assignment
and increase the blast radius. This boundary separates portal classes, not
individual companies or employees. Docker package installation cannot complete
in the no-NAT private topology without controlled repository access; a
production deployment should use a patched, pre-baked, signed AMI or approved
egress rather than depending on first-boot package installation.

### 5. RDS Placement and Database Isolation

Use one encrypted PostgreSQL `db.t3.micro` instance in a two-AZ DB subnet group.
The assignment instance may be Single-AZ, but it must not be described as highly
available. Automated backups, deletion protection, and a deliberate final
snapshot policy will be configured according to the environment.

RDS generates the master password and manages it in Secrets Manager, so the
plaintext password never enters Terraform configuration, plans, or state. Only
the managed secret ARN is exposed as a sensitive output. Deletion protection is
enabled automatically for production and disabled for non-production assignment
testing unless explicitly overridden; production also requires a final snapshot.

Use a shared database and shared schema with mandatory immutable tenant keys:

- Company requests are restricted by `company_id`.
- Bureau requests are restricted by `bureau_id` plus an authoritative
  bureau-to-company assignment table.
- Employee requests are restricted by both `company_id` and `employee_id`.

The application/database design requires PostgreSQL Row Level Security (RLS) on
every tenant-owned table and separate non-owner database roles without
`SUPERUSER` or `BYPASSRLS`. These tables, policies, roles, migrations, and
cross-tenant integration tests are not implemented in this infrastructure
repository. A future application must derive tenant context from verified
server-side identity and membership data, set it transaction-locally, reject
client-supplied tenant headers, and clear transaction state before pool reuse.

RDS requires TLS using `rds.force_ssl`. Database-client certificate verification
is a requirement but is not demonstrated by the placeholder application, which
does not connect to PostgreSQL.

**Trade-off:** Shared-schema RLS fits one micro RDS instance and centralizes
migrations, but a database policy or privileged-role error has a broad blast
radius. Production should evaluate database-per-tenant for high-risk or large
customers, use Multi-AZ RDS, read replicas where justified, tested point-in-time
recovery, and stricter privileged database access.

### 6. S3 Prefix and Bucket Policy Model

Use an encrypted, versioned payroll-document bucket with Object Ownership set to
bucket-owner-enforced and all public access blocked. Use SSE-S3 for the
assignment to avoid introducing customer-managed KMS resources. A bucket policy
explicitly denies non-TLS requests. A simple lifecycle rule retains current
objects, expires noncurrent versions after the configured retention period, and
removes incomplete multipart uploads after seven days.

Objects use separate portal and tenant prefixes:

- `companies/<company_id>/...`
- `bureaus/<bureau_id>/...`
- `employees/<company_id>/<employee_id>/...`

Each portal role receives object permissions only for its top-level prefix.
`ListBucket` and version listing are separately constrained with `s3:prefix`.
The bucket policy explicitly denies each portal role from every object namespace
except its own, including unknown future prefixes. It also denies bucket
administration and rejects listing outside the role's prefix. This provides an
independent resource-policy boundary even if a broader identity policy is
attached later. Applications must generate object keys from authenticated
server-side context rather than accepting arbitrary keys from requests.

Deployment artifacts must not be stored in this payroll document bucket. A
future deployment pipeline should use a separate encrypted artifact store so
executable content and sensitive payroll records do not share a trust boundary.

**Trade-off:** A portal instance role can access all tenants of that portal, so
prefix policy alone does not isolate Company A from Company B. Production should
consider per-tenant S3 access points, roles with trusted session tags, separate
buckets for high-risk tenants, customer-managed KMS keys, and malware scanning.

### 7. IAM Role Boundaries

Terraform creates three application instance roles. Three corresponding
deployment roles are required by the intended workflow but are not provisioned
in this repository. Application roles share only the minimal Session Manager
channel actions plus the message transport operations required for SSM Run
Command; unlike `AmazonSSMManagedInstanceCore`, the custom policy does not grant
account-wide Parameter Store reads. Data and logging access are defined
separately per portal.

Each application role may:

- Read and write only its portal's document prefix.
- Read only `/payroll/<environment>/<portal>/...` SSM parameters.
- Write only its portal's CloudWatch log streams.
- Use Session Manager without accepting inbound administrative ports. The
  required message-channel actions cannot be resource-scoped.

Any separately provisioned GitHub deployment roles must trust GitHub's OIDC
provider only for the exact repository, protected branch/environment, and
workflow. They must be limited to one artifact prefix and tagged target and must
not read payroll documents or application secrets. The workflow applies an
inline session-policy ceiling, but that is not evidence that the external base
roles or trust policies are correctly configured.

Policies avoid wildcard resources where AWS supports resource scoping. Human
administration and Terraform execution are separate from application roles.
There are no IAM users or static AWS access keys for CI/CD.

**Trade-off:** Three parallel policy sets require maintenance but prevent a
single shared role from collapsing the portal boundary. Production should add
separate AWS accounts, organization service control policies, permission
boundaries, centralized identity, and just-in-time privileged access.

### 8. Security Groups and NACLs

Use one security group per portal and one for RDS:

- Portal ingress: no direct internet ingress. A future load-balancer security
  group may reach only the corresponding portal group on the application port.
- SSH: disabled by default. An exceptional routed VPN or bastion CIDR can be
  configured, but `0.0.0.0/0` is rejected and SSM remains the preferred design.
- Portal egress: TCP 5432 only to the RDS security group in the base assignment
  topology, plus DNS to the VPC resolver. Endpoint-specific TCP 443 rules can be
  added with VPC endpoints.
- RDS ingress: TCP 5432 only from the three named portal security groups.
- No portal security group accepts traffic from another portal security group.

Use a separate stateless NACL for each portal application subnet. Explicitly
deny the other portal subnet CIDRs while permitting required database traffic.
The database NACL permits PostgreSQL only from portal subnet CIDRs and the
corresponding return traffic. Exact ephemeral port rules will match the host
operating-system range and be tested rather than assumed.

Security groups are the primary network control because they are stateful and
can reference identities. NACLs are a coarse second boundary; they cannot
enforce application tenant identity and require broader return-path rules.
They prevent direct portal-to-portal lateral traffic if application logic fails,
but cannot isolate tenant rows inside the shared database. PostgreSQL RLS and
separate non-owner runtime roles remain mandatory.

**Trade-off:** NACL complexity can cause outages without preventing attacks
already permitted through the same subnet. Production should add centralized
network telemetry, WAF protections, flow-log analysis, and account-level
segmentation, while retaining simple, reviewed NACL rules.

### 9. Secrets Management

Use RDS-managed Secrets Manager credentials for the database master user. RDS
generates, stores, and rotates that password without exposing its value to
Terraform. Use SSM Parameter Store Standard `SecureString` parameters with the
AWS-managed SSM encryption key for other assignment secrets. Both approaches
keep plaintext out of Git, Terraform inputs, EC2 user data, Docker images,
GitHub Actions, and command output.

Terraform defines IAM access to parameter paths but creates no SSM parameter
values. A future authorized bootstrap process must create `SecureString` values,
and applications must retrieve only their portal path at runtime without logging
values. Narrower runtime database credentials, rotation, and emergency
revocation are required but are not implemented or tested here.

**Trade-off:** RDS-managed Secrets Manager credentials incur a per-secret charge
but avoid plaintext Terraform state and provide managed rotation. Production
should use customer-managed KMS keys with tightly scoped key policies and
separate non-master runtime database credentials. Secret retrieval must not be
performed through Terraform because state can retain values.

### 10. CI/CD Deployment

GitHub Actions checks Terraform formatting and validation, runs unit tests, a
Docker build, and endpoint smoke tests on every push to `main`. Manual dispatch
selects Frontend, Backend, or AI and a target environment; this service taxonomy
is not mapped to the Companies, Bureaus, and Employees EC2 topology. Deployment
is skipped unless a manual run explicitly enables it.

When manually enabled, the intended workflow requests AWS credentials using
OIDC, exports the tested image, verifies a digest, uploads it to a dedicated S3
artifact prefix, and invokes SSM on a tagged instance. The artifact bucket,
OIDC roles, instance read policy, target mapping, and private service connectivity
are external prerequisites and are not created by this Terraform. The
Terraform-managed, account-owned SSM document invokes a fixed root-owned script with
validated parameters. This narrows command execution but does not make the
unprovisioned external roles, artifact path, or target mapping production-ready.

SSM remains preferred over SSH because it requires no inbound management port,
host key distribution, or private SSH key in GitHub. However, SSM Run Command,
artifact retrieval, and CloudWatch agent delivery require interface/gateway
endpoints or other egress that the no-NAT assignment topology does not provide.
The pipeline can be reviewed statically but must not be represented as a working
live deployment until that connectivity is added.

**Trade-off:** Shipping image archives through S3 is slower and less capable
than a container registry. Production should use ECR image scanning and signing,
immutable launch templates, Auto Scaling or a managed container platform, staged
rollouts, automated rollback, and deployment provenance attestations.

## Monitoring Consequences

Each portal has distinct application and infrastructure CloudWatch log groups
and an EC2 CPU alarm. RDS has a database-connection alarm. Missing metrics are
treated as breaching. Alarm and recovery events publish to an operational SNS
topic; email delivery is optional and requires confirmation. The assignment does
not add KMS for SNS because KMS is outside its permitted service list, so alert
payloads must contain no PII, payroll values, credentials, or secrets. No agent
or log driver delivers EC2 logs in the base network.

Within the allowed services, this provides basic detection but not a full audit
or threat-detection platform. Production should add CloudTrail, AWS Config,
GuardDuty, Security Hub, VPC Flow Logs, immutable security-log storage, and
automated detection of `RDS publicly_accessible = true`.

## Consequences

### Positive

- Cross-portal compute, IAM, S3, parameter-path, and log-group boundaries are
  explicit and independently reviewable; customer-level data and deployment
  boundaries remain design requirements.
- RDS is unreachable from the public internet.
- The intended CI/CD design has no static cloud or host credentials and exposes
  no management port.
- The design can be validated without creating live resources.
- The assessment architecture uses only the stated service families.

### Negative and Residual Risks

- Private EC2 instances have no SSM, artifact, update, or log-delivery path in
  the no-NAT base topology.
- Single instances and Single-AZ RDS are not highly available.
- Shared RDS and portal-wide instance roles retain a portal-level blast radius.
- NACLs cannot enforce user or customer identity.
- SSM Parameter Store rotation is operational rather than managed.
- Free-tier limits can be exceeded and must be monitored if resources are
  deployed.

## Alternatives Rejected

- **One shared EC2 instance:** rejected because it breaks the required compute
  boundary and gives a compromise access to all portal processes and roles.
- **Public EC2 for working SSM egress:** rejected by the revised security
  requirement because application resources must not be publicly routable.
- **NAT gateway:** rejected for the assignment because of avoidable continuous
  cost. It remains a production option for controlled general egress.
- **SSH deployment:** rejected because it adds an inbound management path and
  long-lived private-key handling.
- **Database per customer:** rejected for the assignment because a micro RDS
  footprint cannot operate and manage many databases cost-effectively. It
  remains a production option for higher-isolation tenants.
- **Schema per tenant:** rejected because migrations and onboarding become more
  complex while privileged database roles still span schemas.
- **Secrets in Terraform:** rejected because sensitive values can persist in
  plans and state.
- **One IAM role for all portals:** rejected because it would make AWS-level
  portal isolation impossible.

## Required Validation

Before this ADR can move to Accepted, the implementation must demonstrate:

- Terraform formatting, validation, linting, and static security checks.
- No public RDS route, address, or security-group ingress.
- IAM policy tests for allowed and denied cross-portal S3/SSM operations.
- Database integration tests that attempt cross-company, unassigned-bureau, and
  other-employee queries and receive no rows.
- Verification that pooled connections cannot inherit prior tenant context.
- No SSH listener or security-group rule.
- A CI configuration test showing OIDC and portal-specific target selection,
  plus an explicit connectivity prerequisite for any live SSM deployment.
- Secret and PII scanning of source, images, workflow logs, and Terraform plans.
- An incident exercise for accidental RDS public exposure and recovery.
