#!/bin/bash
# Usage: ./setup-cognito-user.sh <stack-name> <region>
# Example: ./setup-cognito-user.sh demo-tg-sam-infra ap-southeast-1

set -e

STACK_NAME="${1:?Usage: $0 <stack-name> <region>}"
REGION="${2:?Missing region}"

# Get values from stack outputs
POOL_ID=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" \
  --query "Stacks[0].Outputs[?OutputKey=='CognitoUserPoolId'].OutputValue" --output text)
USERNAME=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" \
  --query "Stacks[0].Outputs[?OutputKey=='CognitoAppUsername'].OutputValue" --output text)
PASSWORD=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" \
  --query "Stacks[0].Outputs[?OutputKey=='CognitoAppPassword'].OutputValue" --output text)
GROUP=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" \
  --query "Stacks[0].Outputs[?OutputKey=='CognitoGroupName'].OutputValue" --output text)

echo "User Pool ID: $POOL_ID"
echo "Username:     $USERNAME"
echo "Group:        $GROUP"

echo ""
echo "Creating user..."
aws cognito-idp admin-create-user \
  --user-pool-id "$POOL_ID" \
  --username "$USERNAME" \
  --temporary-password 'TempPass123!@#' \
  --user-attributes Name=email,Value="$USERNAME" Name=email_verified,Value=true \
  --message-action SUPPRESS \
  --region "$REGION"

echo "Setting permanent password..."
aws cognito-idp admin-set-user-password \
  --user-pool-id "$POOL_ID" \
  --username "$USERNAME" \
  --password "$PASSWORD" \
  --permanent \
  --region "$REGION"

echo "Adding to group..."
aws cognito-idp admin-add-user-to-group \
  --user-pool-id "$POOL_ID" \
  --username "$USERNAME" \
  --group-name "$GROUP" \
  --region "$REGION"

echo ""
echo "Done! User created:"
echo "  Username: $USERNAME"
echo "  Password: $PASSWORD"
echo "  Group:    $GROUP"
