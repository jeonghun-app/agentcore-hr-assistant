#!/bin/bash
# AgentCore Deploy Script
# 기존 설정이 있으면 업데이트, 없으면 새로 배포합니다.

set -e

echo "=== AgentCore HR Assistant Agent Deploy ==="

# 현재 디렉토리 확인
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 필수 파일 확인
if [ ! -f "agent.py" ]; then
    echo "Error: agent.py not found"
    exit 1
fi

if [ ! -f "requirements.txt" ]; then
    echo "Error: requirements.txt not found"
    exit 1
fi

# AgentCore CLI 설치 확인
if ! command -v agentcore &> /dev/null; then
    echo "Installing bedrock-agentcore-starter-toolkit..."
    pip install bedrock-agentcore-starter-toolkit
fi

# 기본값 설정
AGENT_NAME="hr_assistant_agent"
AWS_REGION="us-east-1"
PYTHON_RUNTIME="PYTHON_3_12"
KB_REGION="us-east-1"

# 기존 설정 확인
if [ -f ".bedrock_agentcore.yaml" ]; then
    echo ""
    echo "✓ 기존 설정 파일 발견"
    echo ""
    
    # 기존 설정에서 값 읽기 (선택적)
    if grep -q "name: hr_assistant_agent" .bedrock_agentcore.yaml; then
        echo "기존 Agent: $AGENT_NAME"
    fi
    
    read -p "기존 설정을 사용하여 업데이트하시겠습니까? (Y/n): " USE_EXISTING
    USE_EXISTING=${USE_EXISTING:-Y}
    
    if [[ "$USE_EXISTING" =~ ^[Yy]$ ]]; then
        echo "✓ 기존 설정으로 업데이트 배포합니다."
        CONFIGURE_NEEDED=false
    else
        echo "새로운 설정으로 배포합니다."
        CONFIGURE_NEEDED=true
    fi
else
    echo ""
    echo "새로운 Agent를 배포합니다."
    CONFIGURE_NEEDED=true
fi

# 새 설정이 필요한 경우
if [ "$CONFIGURE_NEEDED" = true ]; then
    echo ""
    read -p "Enter Agent Name [$AGENT_NAME]: " INPUT_AGENT_NAME
    AGENT_NAME=${INPUT_AGENT_NAME:-$AGENT_NAME}
    
    read -p "Enter AWS Region [$AWS_REGION]: " INPUT_AWS_REGION
    AWS_REGION=${INPUT_AWS_REGION:-$AWS_REGION}
    
    read -p "Enter Python Runtime [$PYTHON_RUNTIME]: " INPUT_PYTHON_RUNTIME
    PYTHON_RUNTIME=${INPUT_PYTHON_RUNTIME:-$PYTHON_RUNTIME}
    
    echo ""
    echo "Configuring AgentCore..."
    agentcore configure \
        --entrypoint agent.py \
        --name "$AGENT_NAME" \
        --deployment-type direct_code_deploy \
        --runtime "$PYTHON_RUNTIME" \
        --requirements-file requirements.txt \
        --region "$AWS_REGION" \
        --protocol HTTP \
        --non-interactive
    
    echo "✓ 설정 완료"
fi

# Model ID 입력
echo ""
DEFAULT_MODEL_ID="arn:aws:bedrock:us-east-1:0000000000:inference-profile/global.anthropic.claude-sonnet-4-20250514-v1:0"
read -p "Enter Model ID or ARN [$DEFAULT_MODEL_ID]: " MODEL_ID
MODEL_ID=${MODEL_ID:-$DEFAULT_MODEL_ID}

# Knowledge Base ID 입력
echo ""
read -p "Enter Knowledge Base ID (optional, press Enter to skip): " KNOWLEDGE_BASE_ID
if [ -n "$KNOWLEDGE_BASE_ID" ]; then
    read -p "Enter Knowledge Base Region [$KB_REGION]: " INPUT_KB_REGION
    KB_REGION=${INPUT_KB_REGION:-$KB_REGION}
    
    # Knowledge Base 권한 설정 여부 확인
    echo ""
    read -p "Add Knowledge Base permissions to execution role? (Y/n): " ADD_KB_PERMS
    ADD_KB_PERMS=${ADD_KB_PERMS:-Y}
fi

echo ""
echo "=== 배포 정보 ==="
echo "  Agent Name: $AGENT_NAME"
echo "  Region: $AWS_REGION"
echo "  Runtime: $PYTHON_RUNTIME"
echo "  Model ID: $MODEL_ID"
echo "  Knowledge Base ID: ${KNOWLEDGE_BASE_ID:-Not set}"
echo "  KB Region: $KB_REGION"
echo ""

# 환경 변수 설정
ENV_VARS="--env MODEL_ID=$MODEL_ID"
if [ -n "$KNOWLEDGE_BASE_ID" ]; then
    ENV_VARS="$ENV_VARS --env KNOWLEDGE_BASE_ID=$KNOWLEDGE_BASE_ID --env KB_REGION=$KB_REGION"
fi

# Knowledge Base 권한 추가 (필요한 경우)
if [ -n "$KNOWLEDGE_BASE_ID" ] && [[ "$ADD_KB_PERMS" =~ ^[Yy]$ ]]; then
    echo ""
    echo "=== Adding Knowledge Base Permissions ==="
    
    # .bedrock_agentcore.yaml에서 execution role 이름 추출
    if [ -f ".bedrock_agentcore.yaml" ]; then
        EXECUTION_ROLE=$(grep "execution_role:" .bedrock_agentcore.yaml | head -1 | awk '{print $2}')
        if [ -n "$EXECUTION_ROLE" ]; then
            ROLE_NAME=$(echo "$EXECUTION_ROLE" | awk -F'/' '{print $NF}')
            POLICY_NAME="BedrockAgentCoreRuntimeExecutionPolicy-${AGENT_NAME}"
            ACCOUNT_ID=$(echo "$EXECUTION_ROLE" | awk -F':' '{print $5}')
            
            echo "Role Name: $ROLE_NAME"
            echo "Policy Name: $POLICY_NAME"
            echo "Account ID: $ACCOUNT_ID"
            echo ""
            
            # 현재 정책 가져오기
            echo "Fetching current policy..."
            aws iam get-role-policy \
                --role-name "$ROLE_NAME" \
                --policy-name "$POLICY_NAME" \
                --region "$AWS_REGION" \
                --query 'PolicyDocument' \
                --output json > /tmp/current_policy.json 2>/dev/null
            
            if [ $? -ne 0 ]; then
                echo "Policy not found, creating new one..."
                echo '{"Version": "2012-10-17", "Statement": []}' > /tmp/current_policy.json
            fi
            
            # Knowledge Base 권한 추가
            echo "Adding Knowledge Base permissions..."
            cat /tmp/current_policy.json | jq '.Statement += [
                {
                    "Sid": "BedrockKnowledgeBaseAccess",
                    "Effect": "Allow",
                    "Action": [
                        "bedrock:Retrieve",
                        "bedrock:RetrieveAndGenerate"
                    ],
                    "Resource": "arn:aws:bedrock:'$KB_REGION':'$ACCOUNT_ID':knowledge-base/*"
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
            ] | .Statement |= unique_by(.Sid)' > /tmp/updated_policy.json
            
            if [ $? -eq 0 ]; then
                # IAM 정책 업데이트
                echo "Updating IAM role policy..."
                aws iam put-role-policy \
                    --role-name "$ROLE_NAME" \
                    --policy-name "$POLICY_NAME" \
                    --policy-document file:///tmp/updated_policy.json \
                    --region "$AWS_REGION"
                
                if [ $? -eq 0 ]; then
                    echo "✓ Knowledge Base permissions added successfully"
                else
                    echo "⚠ Warning: Failed to update IAM policy. You may need to add permissions manually."
                fi
            else
                echo "⚠ Warning: jq command failed. Please ensure jq is installed."
            fi
            
            # 임시 파일 정리
            rm -f /tmp/current_policy.json /tmp/updated_policy.json
        else
            echo "⚠ Warning: Could not extract execution role from config"
        fi
    else
        echo "⚠ Warning: .bedrock_agentcore.yaml not found"
    fi
    echo ""
fi

# AgentCore 배포
echo "Deploying to AgentCore..."
agentcore launch --agent "$AGENT_NAME" --auto-update-on-conflict $ENV_VARS

# 상태 확인
echo ""
echo "Checking deployment status..."
agentcore status --agent "$AGENT_NAME" --verbose

echo ""
echo "=== 배포 완료! ==="
echo ""
echo "테스트 명령어:"
echo "  agentcore invoke '{\"prompt\": \"안녕하세요! 연차 정책에 대해 알려주세요.\"}' --agent $AGENT_NAME"
echo ""
echo "Agent ARN 확인:"
echo "  agentcore status --agent $AGENT_NAME --verbose | grep agent_arn"
echo ""
echo "로그 확인:"
echo "  aws logs tail /aws/bedrock-agentcore/runtimes/${AGENT_NAME}-* --follow --region $AWS_REGION"
