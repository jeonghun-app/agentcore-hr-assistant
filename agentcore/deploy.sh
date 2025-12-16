#!/bin/bash
# AgentCore Deploy Script
# 기존 설정이 있으면 업데이트, 없으면 새로 배포합니다.

set -e

echo "=== AgentCore HR Assistant Agent Deploy ==="

# 현재 디렉토리 확인
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 필수 파일 확인
if [ ! -f "agentcore_worker_http.py" ]; then
    echo "Error: agentcore_worker_http.py not found"
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
        --entrypoint agentcore_worker_http.py \
        --name "$AGENT_NAME" \
        --deployment-type direct_code_deploy \
        --runtime "$PYTHON_RUNTIME" \
        --requirements-file requirements.txt \
        --region "$AWS_REGION" \
        --protocol HTTP \
        --non-interactive
    
    echo "✓ 설정 완료"
fi

# Knowledge Base ID 입력
echo ""
read -p "Enter Knowledge Base ID (optional, press Enter to skip): " KNOWLEDGE_BASE_ID
if [ -n "$KNOWLEDGE_BASE_ID" ]; then
    read -p "Enter Knowledge Base Region [$KB_REGION]: " INPUT_KB_REGION
    KB_REGION=${INPUT_KB_REGION:-$KB_REGION}
fi

echo ""
echo "=== 배포 정보 ==="
echo "  Agent Name: $AGENT_NAME"
echo "  Region: $AWS_REGION"
echo "  Runtime: $PYTHON_RUNTIME"
echo "  Knowledge Base ID: ${KNOWLEDGE_BASE_ID:-Not set}"
echo "  KB Region: $KB_REGION"
echo ""

# 환경 변수 설정
ENV_VARS=""
if [ -n "$KNOWLEDGE_BASE_ID" ]; then
    ENV_VARS="--env KNOWLEDGE_BASE_ID=$KNOWLEDGE_BASE_ID --env KB_REGION=$KB_REGION"
fi

# AgentCore 배포
echo "Deploying to AgentCore..."
if [ -n "$ENV_VARS" ]; then
    agentcore launch --agent "$AGENT_NAME" --auto-update-on-conflict $ENV_VARS
else
    agentcore launch --agent "$AGENT_NAME" --auto-update-on-conflict
fi

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
