#!/bin/bash

set -e

# 환경 변수 (기본값 설정)
REGION="${AWS_REGION:-us-east-1}"
AGENT_NAME="${AGENT_NAME:-hr-assistant-agent}"
AGENTCORE_NAME="${AGENTCORE_NAME:-hr_assistant_agent}"
ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text 2>/dev/null)}"

echo "🚀 AgentCore Runtime 배포 시작..."

# 1. 의존성 확인
echo ""
echo "📦 1단계: 의존성 확인"
if [ ! -d "python" ] || [ ! -d "python/strands" ]; then
    echo "의존성 디렉토리가 없습니다. 생성 중..."
    mkdir -p python
    pip3 install bedrock-agentcore strands-agents boto3 -t python/ \
        --platform manylinux2014_aarch64 \
        --python-version 3.12 \
        --only-binary=:all: --quiet
    
    # 최적화
    find python -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
    find python -type d -name "*.dist-info" -exec rm -rf {} + 2>/dev/null || true
    find python -type d -name "tests" -exec rm -rf {} + 2>/dev/null || true
else
    echo "✅ 기존 의존성 디렉토리 사용"
fi

# Layer 압축
if [ ! -f "agentcore_layer.zip" ]; then
    zip -r agentcore_layer.zip python -q
fi
echo "✅ Layer 준비: $(du -h agentcore_layer.zip | cut -f1)"

# 2. ECR 리포지토리 생성 (이미 있으면 무시)
echo ""
echo "📦 2단계: ECR 리포지토리 확인"
aws ecr describe-repositories --repository-names $AGENT_NAME --region $REGION 2>/dev/null || \
aws ecr create-repository --repository-name $AGENT_NAME --region $REGION
echo "✅ ECR 리포지토리 준비 완료"

# 3. Docker 이미지 빌드 및 푸시
echo ""
echo "📦 3단계: Docker 이미지 빌드"

# Dockerfile은 이미 존재하므로 확인만
if [ ! -f "Dockerfile.agentcore" ]; then
    echo "❌ Dockerfile.agentcore가 없습니다!"
    exit 1
fi
echo "✅ Dockerfile.agentcore 확인 완료"

# 빌드
docker buildx build --platform linux/arm64 \
    -t $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$AGENT_NAME:latest \
    -f Dockerfile.agentcore \
    --load .

echo "✅ Docker 이미지 빌드 완료"

# 4. ECR 로그인 및 푸시
echo ""
echo "📦 4단계: ECR 푸시"
aws ecr get-login-password --region $REGION | \
    docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com

docker push $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$AGENT_NAME:latest
echo "✅ ECR 푸시 완료"

# 5. AgentCore Runtime 생성 또는 업데이트
echo ""
echo "📦 5단계: AgentCore Runtime 생성/업데이트"

# IAM Role ARN
ROLE_ARN="arn:aws:iam::$ACCOUNT_ID:role/slack-bot-worker-role"
CONTAINER_URI="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$AGENT_NAME:latest"

# 기존 Runtime 확인
echo "기존 AgentCore Runtime 확인 중..."

AGENT_ARN=$(aws bedrock-agentcore-control list-agent-runtimes \
    --region $REGION \
    --query "agentRuntimes[?agentRuntimeName=='$AGENTCORE_NAME'].agentRuntimeArn" \
    --output text 2>/dev/null || echo "")

if [ -n "$AGENT_ARN" ] && [ "$AGENT_ARN" != "None" ]; then
    # 기존 Runtime 존재 - 업데이트
    echo "✓ 기존 Runtime 발견: $AGENT_ARN"
    echo "업데이트 시작..."
    
    # ARN에서 ID 추출
    AGENT_ID=$(echo "$AGENT_ARN" | awk -F'/' '{print $NF}')
    
    UPDATE_OUTPUT=$(aws bedrock-agentcore-control update-agent-runtime \
        --agent-runtime-id "$AGENT_ID" \
        --agent-runtime-artifact containerConfiguration={containerUri=$CONTAINER_URI} \
        --role-arn $ROLE_ARN \
        --network-configuration networkMode=PUBLIC \
        --region $REGION \
        --output json 2>&1)
    UPDATE_EXIT=$?
    
    if [ $UPDATE_EXIT -ne 0 ]; then
        echo "❌ 업데이트 실패:"
        echo "$UPDATE_OUTPUT"
        exit 1
    fi
    
    echo "✅ 업데이트 요청 완료"
    SHOULD_WAIT=true
else
    # 새로 생성
    echo "새 Runtime 생성 중..."
    echo "  Name: $AGENTCORE_NAME"
    echo "  Container: $CONTAINER_URI"
    echo "  Role: $ROLE_ARN"
    echo "  Region: $REGION"
    echo ""
    echo "AWS CLI 호출 중... (최대 60초 대기)"
    
    # 타임아웃 추가
    CREATE_OUTPUT=$(timeout 60 aws bedrock-agentcore-control create-agent-runtime \
        --agent-runtime-name $AGENTCORE_NAME \
        --agent-runtime-artifact containerConfiguration={containerUri=$CONTAINER_URI} \
        --network-configuration networkMode=PUBLIC \
        --role-arn $ROLE_ARN \
        --region $REGION \
        --output json 2>&1)
    CREATE_EXIT=$?

    if [ $CREATE_EXIT -eq 124 ]; then
        echo "❌ 타임아웃: AWS CLI 명령이 60초 내에 응답하지 않았습니다"
        echo "수동으로 확인하세요:"
        echo "aws bedrock-agentcore-control list-agent-runtimes --region $REGION"
        exit 1
    elif [ $CREATE_EXIT -ne 0 ]; then
        echo "❌ 생성 실패 (exit code: $CREATE_EXIT):"
        echo "$CREATE_OUTPUT"
        exit 1
    fi
    
    AGENT_ARN=$(echo "$CREATE_OUTPUT" | jq -r '.agentRuntimeArn')
    echo "✅ 생성 요청 완료: $AGENT_ARN"
    SHOULD_WAIT=true
fi

# 상태 확인 대기
if [ "$SHOULD_WAIT" = "true" ]; then
    echo "⏳ Runtime 준비 대기 중..."
    
    # ARN에서 ID 추출 (마지막 부분)
    AGENT_ID=$(echo "$AGENT_ARN" | awk -F'/' '{print $NF}')
    
    MAX_WAIT=300
    ELAPSED=0
    while [ $ELAPSED -lt $MAX_WAIT ]; do
        STATUS=$(aws bedrock-agentcore-control get-agent-runtime \
            --agent-runtime-id "$AGENT_ID" \
            --region $REGION \
            --query 'status' \
            --output text 2>/dev/null || echo "UNKNOWN")
        
        if [ "$STATUS" = "READY" ]; then
            echo "✅ Runtime 준비 완료 (${ELAPSED}초)"
            break
        elif [ "$STATUS" = "FAILED" ]; then
            echo "❌ Runtime 실패"
            exit 1
        fi
        
        echo "  상태: $STATUS (${ELAPSED}초)"
        sleep 10
        ELAPSED=$((ELAPSED + 10))
    done
    
    if [ $ELAPSED -ge $MAX_WAIT ]; then
        echo "⚠️  타임아웃"
        exit 1
    fi
fi

# ARN 저장
echo "$AGENT_ARN" > agentcore_arn.txt
echo ""
echo "✅ AgentCore Runtime ARN: $AGENT_ARN"
echo "   (agentcore_arn.txt에 저장됨)"

# 6. 테스트
echo ""
echo "📦 6단계: 테스트"
echo "⏳ 컸테이너 시작 대기 중... (30초)"
sleep 30

echo "Test question: What is 10 times 5?"
SESSION_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')

echo -n '{"prompt":"What is 10 times 5?"}' > /tmp/test_payload.json

aws bedrock-agentcore invoke-agent-runtime \
    --agent-runtime-arn $AGENT_ARN \
    --runtime-session-id $SESSION_ID \
    --payload fileb:///tmp/test_payload.json \
    --region $REGION \
    /tmp/agentcore_response.json

echo "Response:"
cat /tmp/agentcore_response.json | jq .

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎉 AgentCore Runtime 배포 완료!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Agent ARN: $AGENT_ARN"
echo ""
echo "테스트 명령:"
echo "aws bedrock-agentcore invoke-agent-runtime \\"
echo "  --agent-runtime-arn $AGENT_ARN \\"
echo "  --runtime-session-id \$(uuidgen) \\"
echo "  --payload '{\"prompt\":\"연차는 몇일인가요?\"}' \\"
echo "  --region $REGION \\"
echo "  response.json"
