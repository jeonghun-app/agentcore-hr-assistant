#!/bin/bash
# Script to add Knowledge Base permissions to the AgentCore execution role

ROLE_NAME="AmazonBedrockAgentCoreSDKRuntime-us-east-1-8585f11ecb"
POLICY_NAME="BedrockAgentCoreRuntimeExecutionPolicy-hr_assistant_agent"
REGION="us-east-1"
ACCOUNT_ID="081041735764"

echo "=== Adding Knowledge Base Permissions to AgentCore Execution Role ==="
echo ""

# Get the current policy
echo "Step 1: Fetching current policy..."
aws iam get-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-name "$POLICY_NAME" \
  --region "$REGION" \
  --query 'PolicyDocument' \
  --output json > current_policy.json

if [ $? -ne 0 ]; then
  echo "⚠ Policy not found, will create a new one"
  echo '{"Version": "2012-10-17", "Statement": []}' > current_policy.json
fi

echo "✓ Current policy fetched"
echo ""

# Add the Knowledge Base permissions statement
echo "Step 2: Adding Knowledge Base permissions..."
cat current_policy.json | jq '.Statement += [
  {
    "Sid": "BedrockKnowledgeBaseAccess",
    "Effect": "Allow",
    "Action": [
      "bedrock:Retrieve",
      "bedrock:RetrieveAndGenerate"
    ],
    "Resource": "arn:aws:bedrock:'$REGION':'$ACCOUNT_ID':knowledge-base/*"
  },
  {
    "Sid": "BedrockAgentRuntimeAccess",
    "Effect": "Allow",
    "Action": [
      "bedrock-agent-runtime:Retrieve",
      "bedrock-agent-runtime:RetrieveAndGenerate"
    ],
    "Resource": "*"
  }
]' > updated_policy.json

if [ $? -ne 0 ]; then
  echo "Error: Failed to update policy JSON"
  exit 1
fi

echo "✓ Knowledge Base permissions added to policy"
echo ""

# Update the role policy
echo "Step 3: Updating IAM role policy..."
aws iam put-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-name "$POLICY_NAME" \
  --policy-document file://updated_policy.json \
  --region "$REGION"

if [ $? -ne 0 ]; then
  echo "Error: Failed to update role policy"
  exit 1
fi

echo "✓ Role policy updated successfully"
echo ""

# Clean up temporary files
rm -f current_policy.json updated_policy.json

echo "=== Knowledge Base Permissions Added Successfully! ==="
echo ""
echo "Your agent can now:"
echo "  • Access Bedrock Knowledge Bases"
echo "  • Retrieve documents from Knowledge Base"
echo "  • Use RetrieveAndGenerate API"
echo ""
echo "Next steps:"
echo "1. Set KNOWLEDGE_BASE_ID environment variable during deployment"
echo "2. Redeploy your agent: python3 redeploy.py"
echo "3. Test with: agentcore invoke '{\"prompt\": \"연차 정책이 어떻게 되나요?\"}' --agent hr_assistant_agent"
