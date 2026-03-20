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
DB_USER=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" \
  --query "Stacks[0].Outputs[?OutputKey=='DbUsername'].OutputValue" --output text)
DB_PASS_VAL=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" \
  --query "Stacks[0].Outputs[?OutputKey=='DbPassword'].OutputValue" --output text)

echo "Bastion:      $BASTION_ID"
echo "RDS Endpoint: $RDS_ENDPOINT"
echo "Database:     $DB_NAME"
echo "DB User:      $DB_USER"

echo ""
echo "Running setup on bastion via SSM..."
COMMAND_ID=$(aws ssm send-command \
  --instance-ids "$BASTION_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters commands="[
    \"ADMIN_PASS=\$(aws secretsmanager get-secret-value --secret-id $RDS_SECRET --query SecretString --output text --region $REGION | jq -r .password)\",
    \"export PGPASSWORD=\$ADMIN_PASS\",
    \"psql -h $RDS_ENDPOINT -U dbadmin -d $DB_NAME -c \\\"SELECT 1 FROM pg_roles WHERE rolname = '$DB_USER'\\\" | grep -q 1 && echo 'User $DB_USER already exists' || psql -h $RDS_ENDPOINT -U dbadmin -d $DB_NAME -c \\\"CREATE USER $DB_USER WITH PASSWORD '$DB_PASS_VAL'; GRANT CONNECT ON DATABASE $DB_NAME TO $DB_USER; GRANT CREATE ON DATABASE $DB_NAME TO $DB_USER;\\\"\"
  ]" \
  --region "$REGION" \
  --query "Command.CommandId" --output text)

echo "Command ID: $COMMAND_ID"
echo "Waiting for result..."
sleep 10

aws ssm get-command-invocation \
  --command-id "$COMMAND_ID" \
  --instance-id "$BASTION_ID" \
  --region "$REGION" \
  --query "[Status, StandardOutputContent, StandardErrorContent]" --output text

echo ""
echo "Done! Database user:"
echo "  Username: $DB_USER"
echo "  Password: $DB_PASS_VAL"
echo "  Privilege: CONNECT + CREATE on $DB_NAME"
