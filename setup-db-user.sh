#!/bin/bash
# Usage: ./setup-db-user.sh <stack-name> <region>
# Example: ./setup-db-user.sh demo-tg-sam-infra ap-southeast-1

set -e

STACK_NAME="${1:?Usage: $0 <stack-name> <region>}"
REGION="${2:?Missing region}"

# Get values from stack outputs
BASTION_ID=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" \
  --query "Stacks[0].Outputs[?OutputKey=='BastionInstanceId'].OutputValue" --output text)
RDS_ENDPOINT=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" \
  --query "Stacks[0].Outputs[?OutputKey=='RdsEndpoint'].OutputValue" --output text)
RDS_SECRET=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" \
  --query "Stacks[0].Outputs[?OutputKey=='RdsAdminSecretArn'].OutputValue" --output text)
DB_NAME=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" \
  --query "Stacks[0].Outputs[?OutputKey=='RdsDbName'].OutputValue" --output text)

echo "Bastion:      $BASTION_ID"
echo "RDS Endpoint: $RDS_ENDPOINT"
echo "Database:     $DB_NAME"

echo ""
echo "Running SQL on bastion via SSM..."
COMMAND_ID=$(aws ssm send-command \
  --instance-ids "$BASTION_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters "commands=[
    'DB_PASS=\$(aws secretsmanager get-secret-value --secret-id \"$RDS_SECRET\" --query SecretString --output text --region $REGION | jq -r .password)',
    'PGPASSWORD=\$DB_PASS psql -h $RDS_ENDPOINT -U dbadmin -d $DB_NAME -c \"DO \\$\\$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = \\\"dbuser\\\") THEN CREATE USER dbuser WITH PASSWORD \\\"dbpass\\\"; GRANT CONNECT ON DATABASE $DB_NAME TO dbuser; GRANT CREATE ON DATABASE $DB_NAME TO dbuser; RAISE NOTICE \\\"Created user dbuser\\\"; ELSE RAISE NOTICE \\\"User dbuser already exists\\\"; END IF; END \\$\\$;\"'
  ]" \
  --region "$REGION" \
  --query "Command.CommandId" --output text)

echo "Command ID: $COMMAND_ID"
echo "Waiting for result..."
sleep 5

aws ssm get-command-invocation \
  --command-id "$COMMAND_ID" \
  --instance-id "$BASTION_ID" \
  --region "$REGION" \
  --query "[Status, StandardOutputContent, StandardErrorContent]" --output text

echo ""
echo "Done! Database user:"
echo "  Username: dbuser"
echo "  Password: dbpass"
echo "  Privilege: CONNECT + CREATE on $DB_NAME"
