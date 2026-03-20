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

- Per-app Secrets Manager secrets - created by app team's template
- Per-app schemas - auto-created by app team's Lambda on first request

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
| `CognitoGroupName` | App teams (as AllowedCognitoGroup) |
| `CognitoAppUsername` | App teams (create after deploy - see setup) |
| `CognitoAppPassword` | App teams (create after deploy - see setup) |
| `RdsAdminSecretArn` | Infra team only - do NOT share |
| `RdsSecurityGroupId` | Infra team |
| `BastionInstanceId` | Infra team - connect via Session Manager |

## Setup for lab

After deploying the infra stack:

### 1. Create a shared Cognito user

The template creates the `app-user-group` group automatically. Create a user and add to the group:

```bash
# Create user
aws cognito-idp admin-create-user \
  --user-pool-id <CognitoUserPoolId> \
  --username app-user@lab.local \
  --temporary-password 'TempPass123!@#' \
  --user-attributes Name=email,Value=app-user@lab.local Name=email_verified,Value=true \
  --message-action SUPPRESS \
  --region <region>

# Set permanent password
aws cognito-idp admin-set-user-password \
  --user-pool-id <CognitoUserPoolId> \
  --username app-user@lab.local \
  --password 'LabPass123!@#' \
  --permanent \
  --region <region>

# Add to group
aws cognito-idp admin-add-user-to-group \
  --user-pool-id <CognitoUserPoolId> \
  --username app-user@lab.local \
  --group-name app-user-group \
  --region <region>
```

### 2. Create a shared database user

Connect to bastion:

```bash
aws ssm start-session --target <BastionInstanceId> --region <region>
```

Inside the bastion:

```bash
DB_PASS=$(aws secretsmanager get-secret-value \
  --secret-id <RdsAdminSecretArn> \
  --query 'SecretString' --output text | jq -r '.password')

PGPASSWORD=$DB_PASS psql \
  -h <RdsEndpoint> \
  -U dbadmin \
  -d <RdsDbName>
```

Then run:

```sql
CREATE USER labuser WITH PASSWORD 'labpass123';
GRANT CONNECT ON DATABASE appdb TO labuser;
GRANT CREATE ON DATABASE appdb TO labuser;
```

The `CREATE` privilege allows each team's Lambda to auto-create its own schema (named `<project>_<environment>`).

### 3. Distribute to all teams

All teams receive the same values:

```
CognitoUserPoolId:    <from stack outputs>
CognitoUserPoolArn:   <from stack outputs>
AllowedCognitoGroup:  app-user-group
VpcId:                <from stack outputs>
PrivateSubnetIds:     <from stack outputs>
RDS endpoint:         <RdsEndpoint from stack outputs>
Database name:        <RdsDbName from stack outputs>
Database username:    labuser
Database password:    labpass123
Cognito username:     app-user@lab.local
Cognito password:     LabPass123!@#
```

Each team's Lambda auto-creates its own schema based on its `Project` and `Environment` parameters (e.g., `my_project_dev`). No per-team setup needed.

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

## Cleanup

```bash
make delete
```

Note: Cognito DeletionProtection is ACTIVE for prod only. For dev/staging, stack deletes cleanly.
