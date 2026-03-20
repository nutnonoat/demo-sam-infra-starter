# demo-sam-infra-starter

Shared infrastructure template for serverless applications. Deployed once by the infra team.

## What it creates

| Resource | Description |
|---|---|
| VPC | With 2 private subnets, 1 public subnet across 2 AZs |
| VPC Endpoint | Secrets Manager (interface endpoint with private DNS) |
| RDS PostgreSQL 17 | In private subnets, encrypted, admin password auto-managed |
| Bastion Host | t4g.small in public subnet, Session Manager access, psql pre-installed |
| Cognito User Pool | Centralized user management, email-based login |
| Security Groups | For RDS, VPC endpoints, and bastion |

## What it does NOT create

- Per-app database users/schemas - created via `setup-teams.sql` (see setup below)
- Per-app Cognito groups - created via CLI (see setup below)
- Per-app Secrets Manager secrets - created by app team's template

## Parameters

| Parameter | Default | Description |
|---|---|---|
| `Project` | - | Project name for resource naming |
| `Environment` | `dev` | `dev`, `staging`, or `prod` |
| `VpcCidr` | `10.0.0.0/16` | VPC CIDR block |
| `PrivateSubnet1Cidr` | `10.0.1.0/24` | First private subnet |
| `PrivateSubnet2Cidr` | `10.0.2.0/24` | Second private subnet |
| `PublicSubnetCidr` | `10.0.100.0/24` | Public subnet (bastion) |
| `RdsInstanceClass` | `db.t4g.large` | RDS instance size |
| `RdsDbName` | `appdb` | Default database name |
| `RdsAllocatedStorage` | `20` | Storage in GB |

## Files

| File | Description |
|---|---|
| `template.yaml` | CloudFormation template |
| `setup-teams.sql` | SQL to create 70 database users and schemas in bulk |
| `team-credentials.csv` | Pre-generated credentials for distribution to teams |
| `samconfig.toml` | Deploy configuration |
| `Makefile` | Deploy/delete commands |

## Deploy

```bash
make deploy
```

SAM prompts for parameters interactively and saves to `samconfig.toml`.

## Outputs

After deploy, note these values:

| Output | Who needs it |
|---|---|
| `VpcId` | App teams |
| `PrivateSubnetIds` | App teams |
| `PublicSubnetId` | Infra team |
| `RdsEndpoint` | App teams (for Secrets Manager update) |
| `RdsDbName` | App teams (for Secrets Manager update) |
| `CognitoUserPoolId` | App teams |
| `CognitoUserPoolArn` | App teams |
| `RdsAdminSecretArn` | Infra team only - do NOT share |
| `RdsSecurityGroupId` | Infra team |
| `BastionInstanceId` | Infra team - connect via Session Manager |

## Setup teams (bulk)

After deploying the infra stack, run these steps to prepare credentials for all teams.

### 1. Create database users and schemas

Connect to the bastion and run the SQL file:

```bash
# Connect to bastion
aws ssm start-session --target <BastionInstanceId> --region <region>
```

Inside the bastion:

```bash
# Get admin password
DB_PASS=$(aws secretsmanager get-secret-value \
  --secret-id <RdsAdminSecretArn> \
  --query 'SecretString' --output text | jq -r '.password')

# Run bulk setup (creates 70 users and schemas)
PGPASSWORD=$DB_PASS psql \
  -h <RdsEndpoint> \
  -U dbadmin \
  -d <RdsDbName> \
  -f setup-teams.sql
```

This creates:
- `dbuser001` through `dbuser070` (each with their own password)
- `app001` through `app070` schemas (each owned by the corresponding user)
- Each user can only access their own schema

### 2. Create Cognito groups

Run from your local machine or bastion:

```bash
for i in $(seq 1 70); do
  num=$(printf "%03d" $i)
  aws cognito-idp create-group \
    --user-pool-id <CognitoUserPoolId> \
    --group-name "team-${num}-users" \
    --description "Users for team-${num}" \
    --region <region>
done
```

### 3. Distribute to teams

Each team receives:

| Value | Source |
|---|---|
| `CognitoUserPoolId` | Stack outputs |
| `CognitoUserPoolArn` | Stack outputs |
| `AllowedCognitoGroup` | `team-<NNN>-users` |
| `VpcId` | Stack outputs |
| `PrivateSubnetIds` | Stack outputs |
| RDS endpoint | `RdsEndpoint` from stack outputs |
| Database name | `RdsDbName` from stack outputs |
| Database username | From `team-credentials.csv` (e.g., `dbuser001`) |
| Database password | From `team-credentials.csv` (e.g., `dbpass001`) |
| Schema name | From `team-credentials.csv` (e.g., `app001`) |

The app team uses the RDS details to update their Secrets Manager secret after deploying their stack (see backend starter README Step 4).

## Connect to bastion

```bash
aws ssm start-session --target <BastionInstanceId> --region <region>
```

Then connect to RDS:

```bash
DB_PASS=$(aws secretsmanager get-secret-value \
  --secret-id <RdsAdminSecretArn> \
  --query 'SecretString' --output text | jq -r '.password')

PGPASSWORD=$DB_PASS psql \
  -h <RdsEndpoint> \
  -U dbadmin \
  -d <RdsDbName>
```

## Onboarding a single team (ad-hoc)

If you need to add a team outside of the bulk setup:

### 1. Connect to RDS via bastion (see above)

### 2. Create database user and schema

```sql
CREATE USER <username> WITH PASSWORD '<password>';
CREATE SCHEMA <schema> AUTHORIZATION <username>;
GRANT CONNECT ON DATABASE <RdsDbName> TO <username>;
REVOKE ALL ON SCHEMA public FROM <username>;
```

### 3. Create Cognito group

```bash
aws cognito-idp create-group \
  --user-pool-id <CognitoUserPoolId> \
  --group-name <team>-users \
  --description "Users for <team>" \
  --region <region>
```

### 4. Hand off credentials to the team (see distribution table above)

## Cleanup

```bash
make delete
```

Note: Cognito DeletionProtection is ACTIVE for prod only. For dev/staging, stack deletes cleanly.
