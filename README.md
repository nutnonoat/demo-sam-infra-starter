# demo-sam-infra-starter

Shared infrastructure template for serverless applications. Deployed once by the infra team.

## What it creates

| Resource | Description |
|---|---|
| VPC | With 2 private subnets across 2 AZs |
| VPC Endpoint | Secrets Manager (interface endpoint with private DNS) |
| RDS PostgreSQL 16 | In private subnets, encrypted, admin password auto-managed |
| RDS | Connection pooling for Lambda, TLS required |
| Cognito User Pool | Centralized user management, email-based login |
| Security Groups | For RDS and VPC endpoints |

## What it does NOT create

- Per-app database users/schemas — created manually per app (see onboarding below)
- Per-app Cognito groups — created manually per app
- Per-app Secrets Manager secrets — created by app team's template
- NAT Gateway — not needed since Lambda accesses AWS services via VPC endpoints

## Parameters

| Parameter | Default | Description |
|---|---|---|
| `Project` | — | Project name for resource naming |
| `Environment` | `dev` | `dev`, `staging`, or `prod` |
| `VpcCidr` | `10.0.0.0/16` | VPC CIDR block |
| `PrivateSubnet1Cidr` | `10.0.1.0/24` | First private subnet |
| `PrivateSubnet2Cidr` | `10.0.2.0/24` | Second private subnet |
| `RdsInstanceClass` | `db.t4g.medium` | RDS instance size |
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
| `RdsEndpoint` | App teams (as RdsHost) |
| `RdsDbName` | App teams |
| `CognitoUserPoolId` | App teams |
| `CognitoUserPoolArn` | App teams |
| `RdsAdminSecretArn` | Infra team only — do NOT share |
| `RdsSecurityGroupId` | Infra team — add app Lambda SG inbound rules here |
| `RdsEndpoint` | Infra team only — direct RDS access for admin tasks |

## Onboarding a new app team

For each new app, the infra team runs these steps:

### 1. Connect to RDS with admin credentials

```bash
# Get admin password from Secrets Manager
ADMIN_SECRET=$(aws secretsmanager get-secret-value \
  --secret-id <RdsAdminSecretArn> \
  --query 'SecretString' --output text)

# Parse credentials
DB_HOST=$(echo $ADMIN_SECRET | jq -r '.host')
DB_USER=$(echo $ADMIN_SECRET | jq -r '.username')
DB_PASS=$(echo $ADMIN_SECRET | jq -r '.password')
DB_NAME=$(echo $ADMIN_SECRET | jq -r '.dbname')

# Connect (requires psql and network access to RDS — use CloudShell VPC environment or bastion)
PGPASSWORD=$DB_PASS psql -h $DB_HOST -U $DB_USER -d $DB_NAME
```

### 2. Create app-specific database user and schema

```sql
-- Replace 'myapp' with the app name
CREATE USER myapp_user WITH PASSWORD 'generate-a-strong-password';
CREATE SCHEMA myapp AUTHORIZATION myapp_user;
GRANT CONNECT ON DATABASE appdb TO myapp_user;
-- myapp_user can only access the myapp schema
```

### 3. Create Cognito group for the app

```bash
aws cognito-idp create-group \
  --user-pool-id <CognitoUserPoolId> \
  --group-name myapp-users \
  --description "Users for myapp"
```

### 4. Hand off to app team

Provide the following values:

```
CognitoUserPoolId:    <from stack outputs>
CognitoUserPoolArn:   <from stack outputs>
AllowedCognitoGroup:  myapp-users
VpcId:                <from stack outputs>
PrivateSubnetIds:     <from stack outputs>
RdsHost:              <RdsEndpoint from stack outputs>
RdsDbName:            appdb
RdsUsername:           myapp_user
RdsPassword:          <the password you generated in step 2>
```

### 5. After app team's first deploy

Add their Lambda security group to the RDS security group:

```bash
aws ec2 authorize-security-group-ingress \
  --group-id <RdsSecurityGroupId> \
  --protocol tcp \
  --port 5432 \
  --source-group <LambdaSecurityGroupId from app team's stack outputs>
```

## Cleanup

```bash
make delete
```

Note: RDS has `DeletionProtection: false` for dev. Set to `true` for production.
