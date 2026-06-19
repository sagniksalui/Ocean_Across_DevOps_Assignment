# GitHub Actions Security Audit

**Date:** 2026-06-19  
**Scope:** `.github/workflows/deploy.yml` and its documented AWS dependencies

## Findings and Remediation

| Severity | Finding | Hardened control |
| --- | --- | --- |
| High | Action major-version tags were mutable supply-chain references. | Every external action is pinned to a full commit SHA with the release major retained as a comment. |
| High | One `AWS_ROLE_ARN` could require access to all three service targets. The repository does not currently provision or prove that role's policy. | The workflow selects a separate role per service and applies an inline session policy ceiling for one S3 prefix, one SSM document, and one instance. The base roles still must be provisioned with equally narrow policies. |
| High | A mistyped or changed instance variable could direct a root-equivalent SSM command to the wrong host. | The role session is restricted to the exact instance ARN and matching resource tags. The workflow separately verifies account, running state, project, environment, service, and SSM online status. |
| High | Production depended entirely on optional GitHub Environment configuration. | Production now requires manual dispatch, protected `main`, the expected workflow ref, exact typed confirmation, an enable flag, and the GitHub Environment gate. |
| Medium | The image and checksum could be transported together without re-verification between jobs. | The deploy job verifies the GitHub artifact before obtaining AWS credentials, uploads an immutable SSE-S3 object with an AWS checksum, and passes the expected digest independently through SSM. |
| Medium | The deployment stopped the active container before proving the replacement healthy. | A restricted candidate container is health-checked first, and the prior image is retained for a best-effort rollback. |
| Medium | Failure handling printed remote command output and application logs into GitHub logs. | CI now reports only the SSM status and command ID. It does not print remote stdout, stderr, environment variables, or application logs. |
| Medium | Checkout retained GitHub credentials and all actions used broad floating runner/action references. | Checkout credential persistence is disabled, action SHAs are pinned, and the runner is fixed to `ubuntu-24.04`. |

## Required External Controls

The workflow cannot enforce repository or AWS configuration by itself. Before a
live deployment, configure both `dev` and `production` GitHub Environments.
Production must require independent reviewers, prevent self-review, disallow
administrator bypass, and allow protected `main` only.

Set these non-secret Environment variables:

- `AWS_REGION` (`eu-west-2` only)
- `DEPLOYMENT_BUCKET`
- `FRONTEND_INSTANCE_ID`, `BACKEND_INSTANCE_ID`, `AI_INSTANCE_ID`
- `FRONTEND_DEPLOY_ROLE_ARN`, `BACKEND_DEPLOY_ROLE_ARN`, `AI_DEPLOY_ROLE_ARN`
- `PRODUCTION_DEPLOYMENTS_ENABLED` (`true` only after production approval)

Each OIDC role trust policy must restrict `aud` to `sts.amazonaws.com` and `sub`
to the exact repository and GitHub Environment. Its permissions must allow only
the corresponding deployment prefix, tagged instance, approved SSM document,
and read-only status APIs. The workflow's inline session policy is a permissions
ceiling, not a replacement for a least-privilege base policy.

The session policy uses `Resource: "*"` only for the read-only
`DescribeInstances`, `DescribeInstanceInformation`, and `GetCommandInvocation`
status calls, whose request-time target cannot be expressed as a fixed resource
ARN here. No wildcard resource is used for S3 writes or SSM command execution.

The dedicated artifact bucket must not be the payroll document bucket. It must
block public access, enforce TLS and server-side encryption, enable versioning,
and grant each EC2 role read-only access to its service artifact prefix. Private
instances also need SSM interface endpoints and an S3 gateway endpoint, or other
controlled egress; the current no-NAT assessment network does not provide them.

## Residual Risks

- `AWS-RunShellScript` is root-equivalent on the selected EC2 instance. Production
  should use a narrowly parameterized, account-owned SSM document and permit only
  that document ARN.
- A digest protects integrity, not publisher identity. Production should sign
  images and verify signatures against an approved KMS-backed identity.
- The Docker base image is referenced by a moving tag. Pin its digest and add
  vulnerability and secret scanning before production use.
- Terraform currently creates Companies, Bureaus, and Employees backend hosts,
  while this workflow selects Frontend, Backend, and AI service targets. The
  frontend/AI targets must be provisioned and tagged, or the service-to-portal
  deployment model must be clarified. The workflow fails closed on tag mismatch.
- Concurrency and separate roles provide operational service independence, but
  the shared `dev` and `production` GitHub Environments do not authorize users
  per service. Strong team separation requires service-specific environments or
  reusable workflows with separate reviewers and OIDC trust boundaries.
