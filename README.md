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

- Per-app database users/schemas - created manually per app (see onboarding below)
- Per-app Cognito groups - created manually per app
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

## Connect to bastion

```bash
aws ssm start-session --target <BastionInstanceId> --region <region>
```

## Onboarding a new app team

For each new app, the infra team runs these steps:

### 1. Connect to RDS via bastion

```bash
aws ssm start-session --target <BastionInstanceId> --region <region>
```

Then inside the bastion:

```bash
# Get admin password
DB_PASS=$(aws secretsmanager get-secret-value \
  --secret-id <RdsAdminSecretArn> \
  --query 'SecretString' --output text | jq -r '.password')

# Connect (host and dbname from stack outputs)
PGPASSWORD=$DB_PASS psql \
  -h <RdsEndpoint> \
  -U dbadmin \
  -d <RdsDbName>
```

### 2. Create app-specific database user and schema

```sql
-- Replace 'myapp' with the app name, use project_environment format
-- Example: project=my-app, environment=dev -> schema=my_app_dev
CREATE USER myapp_user WITH PASSWORD 'generate-a-strong-password';
CREATE SCHEMA my_app_dev AUTHORIZATION myapp_user;
GRANT CONNECT ON DATABASE <RdsDbName> TO myapp_user;
-- myapp_user can only access the my_app_dev schema
```

### 3. Create Cognito group for the app

```bash
aws cognito-idp create-group \
  --user-pool-id <CognitoUserPoolId> \
  --group-name myapp-users \
  --description "Users for myapp"
```

### 4. Hand off to app team

Provide the following values securely:

```
CognitoUserPoolId:    <from stack outputs>
CognitoUserPoolArn:   <from stack outputs>
AllowedCognitoGroup:  myapp-users
VpcId:                <from stack outputs>
PrivateSubnetIds:     <from stack outputs>
RDS endpoint:         <RdsEndpoint from stack outputs>
Database name:        <RdsDbName from stack outputs>
Database username:    myapp_user
Database password:    <the password you generated in step 2>
```

The app team will use the RDS details to update their Secrets Manager secret after deploying their stack (see backend starter README Step 4).

## Cleanup

```bash
make delete
```

Note: Cognito DeletionProtection is ACTIVE for prod only. For dev/staging, stack deletes cleanly.
