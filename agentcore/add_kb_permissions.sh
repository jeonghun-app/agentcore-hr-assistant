#!/bin/bash
# Add Knowledge Base permissions to AgentCore execution role

set -e

echo "=== Adding Knowledge Base Permissions to AgentCore ==="
echo ""

# 설정 파일에서 역할 정보 추출
if [ ! -f ".bedrock_agentcore.yaml" ]; then
    echo "Error: .bedrock_agentcore.yaml not found"
    echo "Please run this script from the agentcore directory"
    exit 1
fi

# 실행 역할 ARN 추출
EXECUTION_ROLE=$(grep "execution_role:" .bedrock_agentcore.yaml | head -1 | awk '{print $2}')

if [ -z "$EXECUTION_ROLE" ]; then
    echo "Error: Could not find execution_role in .bedrock_agentcore.yaml"
    exit 1
fi

# 역할 이름 추출
ROLE_NAME=$(echo "$EXECUTION_ROLE" | awk -F'/' '{print $NF}')
ACCOUNT_ID=$(echo "$EXECUTION_ROLE" | awk -F':' '{print $5}')
AWS_REGION=${AWS_REGION:-us-east-1}

echo "Role Name: $ROLE_NAME"
echo "Account ID: $ACCOUNT_ID"
echo "Region: $AWS_REGION"
echo ""

# Knowledge Base ID 입력
read -p "Enter Knowledge Base ID: " KB_ID
if [ -z "$KB_ID" ]; then
    echo "Error: Knowledge Base ID is required"
    exit 1
fi

read -p "Enter Knowledge Base Region [ap-northeast-2]: " KB_REGION
KB_REGION=${KB_REGION:-ap-northeast-2}

echo ""
echo "Adding permissions for Knowledge Base: $KB_ID (region: $KB_REGION)"
echo ""

# 정책 문서 생성
POLICY_DOC=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "BedrockKnowledgeBaseAccess",
      "Effect": "Allow",
      "Action": [
        "bedrock:Retrieve",
        "bedrock:RetrieveAndGenerate"
      ],
      "Resource": "arn:aws:bedrock:${KB_REGION}:${ACCOUNT_ID}:knowledge-base/${KB_ID}"
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
  ]
}
EOF
)

# 정책 이름
POLICY_NAME="KnowledgeBaseAccessPolicy"

echo "Policy Document:"
echo "$POLICY_DOC"
echo ""

# 정책 추가
echo "Adding inline policy to role..."
aws iam put-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-name "$POLICY_NAME" \
    --policy-document "$POLICY_DOC" \
    --region "$AWS_REGION"

if [ $? -eq 0 ]; then
    echo ""
    echo "✓ Knowledge Base permissions added successfully!"
    echo ""
    echo "Policy Name: $POLICY_NAME"
    echo "Role: $ROLE_NAME"
    echo ""
    echo "You can verify the policy in AWS Console:"
    echo "https://console.aws.amazon.com/iam/home#/roles/$ROLE_NAME"
else
    echo ""
    echo "✗ Failed to add permissions"
    exit 1
fi
