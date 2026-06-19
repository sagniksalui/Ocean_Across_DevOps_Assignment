# Ocean Across DevOps Assignment

This repository is a security-first reference implementation for a UK payroll
platform. It is an assessment design, not a production accreditation.

## Multi-Tenancy Architecture

### Tenancy model

The assignment uses a **pooled database and shared schema** with an immutable
tenant key on every tenant-owned row. A Company is the primary payroll data
tenant. Bureaus are delegated tenants that may act for explicitly assigned
Companies, and Employees are identities scoped to their employer and their own
employee record.

| Portal | Authoritative request context | Permitted scope |
| --- | --- | --- |
| Companies | `user_id`, `company_id` | The authenticated user's Company memberships and permissions |
| Bureaus | `user_id`, `bureau_id`, `acting_company_id` | Companies with an active bureau-to-company assignment |
| Employees | `user_id`, `company_id`, `employee_id` | The authenticated employee's own permitted payroll data |

This model is appropriate for the assignment because one small RDS instance can
serve all portals, migrations remain centralized, and onboarding does not create
database infrastructure per customer. It depends on consistent application
authorization and PostgreSQL Row-Level Security (RLS), so it has a larger shared
blast radius than database-per-tenant isolation.

The three EC2 instances isolate **portal classes**, not individual customers. A
Companies instance compromise must not grant an Employees or Bureaus AWS role,
but its instance role currently covers all Companies tenants. Customer-level
isolation therefore remains mandatory in the API, PostgreSQL, and S3 object-key
design.

### Establishing tenant context at login

Tenant context is derived from trusted server-side records, never from a tenant
identifier supplied by the login form:

1. The identity service authenticates the user and verifies account state and
   MFA requirements.
2. The backend loads the user's active portal membership from the database.
3. A Company user receives only an active Company membership. An Employee is
   bound to one `company_id` and `employee_id`. A Bureau user must choose from
   Companies present in the authoritative, effective-dated assignment table.
4. If a Bureau changes the Company it is acting for, the backend rechecks the
   assignment and issues a new short-lived session. It does not accept an
   arbitrary Company ID as proof of access.
5. The signed session contains the subject, portal type, acting tenant ID,
   authorization version, audience, issuer, expiry, and token ID. It contains no
   bank details, payroll values, or unnecessary employee data.

Disabled memberships, revoked bureau assignments, and stale authorization
versions fail closed. Sensitive payroll or bank-detail operations should require
recent authentication or step-up MFA.

### Propagating context through API requests

The client sends the signed session using an `Authorization: Bearer` header or a
`Secure`, `HttpOnly`, and appropriate `SameSite` cookie. Middleware performs the
following work before a controller or repository is called:

1. Verify signature, issuer, audience, expiry, portal type, and revocation state.
2. Resolve the immutable request context from verified claims and current
   membership data.
3. Reject client-controlled `X-Tenant-ID`, query-string, or request-body tenant
   values as authorization evidence.
4. Start a database transaction and set transaction-local tenant context with a
   parameterized `set_config` call.
5. Pass a typed, immutable context object through the service layer and include
   the tenant predicate in every tenant-owned query.
6. Commit or roll back the transaction before returning the connection to the
   pool. Transaction-local settings must never leak to another request.

Tokens, session cookies, bank data, and payroll payloads must not be written to
application or audit logs.

### Unsafe and safe tenant-scoped queries

In these examples, `tenant_id` is the immutable Company UUID used as the payroll
data partition key. A domain-facing API may call it `company_id`, but the value
and database boundary must be unambiguous and consistent.

The following query is **unsafe even though it is parameterized**:

```typescript
return database.query(
  `SELECT payroll_record_id, employee_id, pay_period, gross_amount, net_amount
     FROM payroll_records
    WHERE payroll_record_id = $1::uuid`,
  [request.params.payrollRecordId],
);
```

It prevents this parameter from becoming SQL syntax, but it has no tenant
predicate. A user who obtains another record UUID through a log, support ticket,
browser history, or separate defect could retrieve another Company's payroll
record. A UUID is an identifier, not an authorization control.

The corrected version gets `tenantId` from verified request context, sets the RLS
context, and executes an explicit tenant-scoped query on the same transaction and
connection. Every value is a parameter; string concatenation is prohibited.

```typescript
await database.transaction(async (tx) => {
  await tx.query(
    "SELECT set_config('app.tenant_id', $1, true)",
    [requestContext.tenantId],
  );

  return tx.query(
    `SELECT payroll_record_id, employee_id, pay_period, gross_amount, net_amount
       FROM payroll_records
      WHERE tenant_id = $1::uuid
        AND payroll_record_id = $2::uuid`,
    [requestContext.tenantId, payrollRecordId],
  );
});
```

The explicit `tenant_id` predicate is retained even when RLS is enabled. It
documents intent, improves query planning, and provides another check against a
wrong request context. The tenant ID comes from verified middleware, not from
the request payload.

Application `WHERE` clauses are necessary, but they are not sufficient as the
only payroll isolation control:

- One missed predicate in a new endpoint, report, join, background job, or bulk
  export can expose many employees at once.
- A later refactor can weaken a predicate with incorrect `OR` logic or apply it
  to one joined table but not another.
- `INSERT` and `UPDATE` paths also need to prevent writing a different tenant ID;
  a read-only convention does not protect them.
- Application tests and reviews reduce mistakes but cannot make every future
  query correct, and a compromised application process already runs inside that
  trust boundary.

Payroll records and bank details have too much impact for isolation to depend on
a coding convention alone. RLS makes PostgreSQL evaluate a separate policy for
every affected row, including queries whose application-level predicate is
missing.

### PostgreSQL Row-Level Security

RLS provides a database-enforced, default-deny boundary when an application
query accidentally omits its tenant predicate. A representative policy is:

```sql
ALTER TABLE payroll_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE payroll_records FORCE ROW LEVEL SECURITY;

CREATE POLICY payroll_company_isolation
ON payroll_records
FOR ALL
TO payroll_runtime
USING (
  tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::uuid
)
WITH CHECK (
  tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::uuid
);
```

If `app.tenant_id` is absent, the expression does not evaluate to `true`, so no
row is visible or writable. `USING` protects reads, updates, and deletes;
`WITH CHECK` prevents inserting a row for another tenant. Employee policies also
match `employee_id`. Bureau access additionally requires an active row in the
bureau-to-company assignment table for the selected `bureau_id` and Company.

Runtime roles must not own tenant tables and must not have `SUPERUSER` or
`BYPASSRLS`; schema migrations use a separate role unavailable to the
application. PostgreSQL documents that superusers, `BYPASSRLS` roles, and
normally table owners can bypass RLS, while `FORCE ROW LEVEL SECURITY` subjects
the owner to policies in normal operation. See the
[PostgreSQL RLS documentation](https://www.postgresql.org/docs/current/ddl-rowsecurity.html).

RLS is defense in depth, not a substitute for parameterized SQL. A successful
SQL-injection attacker using a role that can change custom session settings may
attempt to change `app.tenant_id`; preventing injection, minimizing database
privileges, and testing negative cross-tenant cases remain mandatory.

### IAM and S3 boundaries

Each portal EC2 instance has a separate IAM role. The Companies role can access
only `companies/*`, Bureaus only `bureaus/*`, and Employees only `employees/*`.
Bucket-policy denies reinforce those identity policies, and public access is
blocked. The application generates keys from authenticated context using:

```text
companies/<company_id>/...
bureaus/<bureau_id>/...
employees/<company_id>/<employee_id>/...
```

This is an independent boundary between portal classes if routing or application
authorization fails. It also prevents a compromised Employees process from
reading Company or Bureau objects with its own instance credentials.

The current EC2 roles are deliberately **not** per-customer roles: the Companies
role can access every object below `companies/`. Nested prefixes organize tenant
objects but do not by themselves enforce Company A versus Company B access.
Production should evaluate trusted STS session tags, per-tenant S3 access points,
separate roles or buckets for high-risk tenants, and customer-managed KMS keys.

### Onboarding

Onboarding is an authorized workflow, not a direct insert from a public request.
Every step records the approving actor, time, tenant identifier, and outcome
without copying payroll or bank data into the audit event.

**New Company**

1. Verify the contract, controller/processor responsibilities, lawful purpose,
   residency requirements, retention schedule, and required security review.
2. Create a random immutable `company_id`, Company record, baseline settings,
   and first administrator membership in one transaction.
3. Send a single-use, short-lived administrator invitation and require MFA
   before payroll or bank permissions are granted.
4. Reserve the virtual S3 namespace `companies/<company_id>/`; object keys are
   generated only by the backend.
5. Run negative authorization tests proving another Company, an unassigned
   Bureau, and an unrelated Employee receive no rows or objects.

**New Bureau**

1. Create an immutable `bureau_id`, Bureau record, and restricted administrator
   invitation. No Company access exists by default.
2. Create each bureau-to-company assignment only after Company approval. Store
   permitted actions, effective dates, approvers, and revocation state.
3. Reserve `bureaus/<bureau_id>/` for Bureau-owned documents. Company payroll
   documents are accessed only through an authorized service workflow, never by
   granting the Bureau role all of `companies/*`.
4. Test that the Bureau can act only for assigned Companies and loses access
   immediately when an assignment expires or is revoked.

The pooled model does not create a new EC2 instance, database, or AWS role for
each Company or Bureau. That keeps onboarding feasible but retains the shared
infrastructure trade-off.

### Offboarding and erasure

Access revocation is immediate; deletion follows an approved retention and
legal-hold decision. Company offboarding also disables its Employee memberships
and Bureau assignments. Bureau offboarding revokes delegated assignments but
does not delete payroll data owned by its Companies.

1. Disable users, API clients, invitations, and assignments; invalidate active
   sessions and rotate tenant-specific credentials or integration secrets.
2. Stop new processing and produce an authorized export or return manifest when
   contractually required. Record checksums and recipient approval, not file
   contents, in the audit trail.
3. Classify data by purpose, statutory retention, litigation hold, and data
   subject request. UK PAYE records generally must be retained for three years
   from the end of the relevant tax year, according to
   [GOV.UK payroll record guidance](https://www.gov.uk/paye-for-employers/keeping-records).
   The final schedule must be approved by the controller's legal or data
   protection owner because other records can have different obligations.
4. Move retained records into a logically closed state with no portal access and
   tightly restricted administrative retrieval. Retention is not permission for
   continued product use.
5. At expiry, delete tenant rows in dependency order and remove every S3 object
   version and delete marker. A delete marker in a versioned bucket is not proof
   of erasure. Automated RDS backups age out under the documented schedule, and
   manual snapshots are deleted when their approved legal basis ends. Until then,
   backup access remains exceptional and restricted. Any restore process must
   reapply deletion tombstones before the database can serve production traffic,
   so an offboarded tenant is not silently resurrected.
6. Verify that tenant logins fail, bureau assignments are inactive, RLS queries
   return no data, S3 version listings are empty, and downstream recipients have
   been notified where required.
7. Retain a minimal, append-only, access-controlled audit record containing
   request and approval IDs, legal basis, data categories, timestamps, deletion
   job results, backup-expiry date, and verification outcome. It must not
   preserve the deleted payroll payload or reusable credentials.

UK GDPR storage limitation requires review and deletion or anonymisation when
personal data is no longer needed; the right to erasure is not absolute where a
legal obligation or legal claim requires retention. See the ICO guidance on
[storage limitation](https://ico.org.uk/for-organisations/uk-gdpr-guidance-and-resources/data-protection-principles/a-guide-to-the-data-protection-principles/storage-limitation/)
and the [right to erasure](https://ico.org.uk/for-organisations/uk-gdpr-guidance-and-resources/individual-rights/individual-rights/right-to-erasure/).

### Trade-offs and production improvements

- A shared schema is inexpensive and operationally simple, but one policy or
  privileged-role error can affect many tenants and tenants share capacity.
- RLS catches missing tenant predicates, but it must be forced, tested for every
  tenant-owned table, and used through non-owner runtime roles.
- Short-lived tenant claims reduce database lookups but can become stale; short
  expiry, authorization versions, and revocation checks reduce that window.
- Portal-specific EC2, IAM, and S3 controls limit cross-portal compromise but do
  not provide customer-level AWS isolation.
- Statutory retention can conflict with an immediate deletion request; access
  must be revoked immediately while retained data is isolated and deleted when
  the documented legal basis ends.
- Production should offer stronger isolation tiers, such as database-per-tenant
  and separate AWS accounts or buckets, for large or high-risk customers.

The model is acceptable for this assignment only if automated tests attempt
cross-Company, unassigned-Bureau, and other-Employee reads and writes and prove
that the API, RLS policies, and S3 access paths all fail closed.
