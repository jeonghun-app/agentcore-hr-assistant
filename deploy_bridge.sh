#!/bin/bash

set -e

echo "🚀 Lambda Bridge 배포 (SQS → AgentCore 연결)..."

# 환경 변수 (기본값 설정)
FUNCTION_NAME="${FUNCTION_NAME:-slack-bot-bridge}"
REGION="${AWS_REGION:-ap-northeast-2}"
ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text 2>/dev/null)}"
QUEUE_NAME="${SQS_QUEUE_NAME:-slack-bot-queue}"

# SQS Queue ARN 가져오기
echo ""
echo "📦 SQS Queue 정보 확인 중..."
if [ -n "${SQS_QUEUE_ARN}" ]; then
    QUEUE_ARN="${SQS_QUEUE_ARN}"
    echo "✅ 환경변수에서 SQS ARN 사용: $QUEUE_ARN"
else
    # SQS Queue ARN 자동 감지
    QUEUE_ARN=$(aws sqs get-queue-attributes \
        --queue-url "https://sqs.$REGION.amazonaws.com/$ACCOUNT_ID/$QUEUE_NAME" \
        --attribute-names QueueArn \
        --region $REGION \
        --query 'Attributes.QueueArn' \
        --output text 2>/dev/null)
    
    if [ -z "$QUEUE_ARN" ] || [ "$QUEUE_ARN" = "None" ]; then
        echo "❌ SQS Queue를 찾을 수 없습니다: $QUEUE_NAME"
        echo "먼저 'python3 create_sqs_queue.py'로 SQS를 생성하세요"
        exit 1
    fi
    echo "✅ SQS ARN 감지: $QUEUE_ARN"
fi

# Slack Bot Token 확인
if [ -z "${SLACK_BOT_TOKEN}" ]; then
    echo ""
    read -p "Slack Bot Token (xoxb-로 시작): " SLACK_BOT_TOKEN
    if [ -z "$SLACK_BOT_TOKEN" ]; then
        echo "❌ Slack Bot Token이 필요합니다"
        exit 1
    fi
fi

# AgentCore Runtime ARN 가져오기
echo ""
if [ -f "agentcore_arn.txt" ]; then
    AGENTCORE_RUNTIME_ARN=$(cat agentcore_arn.txt)
    echo "✅ AgentCore ARN 발견: $AGENTCORE_RUNTIME_ARN"
else
    echo "❌ agentcore_arn.txt 파일이 없습니다"
    echo "먼저 'bash deploy_agentcore.sh'로 AgentCore를 배포하세요"
    exit 1
fi

# 1. IAM 역할 생성
echo ""
echo "📦 1단계: IAM 역할 생성"

ROLE_NAME="slack-bot-bridge-role"

# Trust Policy 생성
cat > trust-policy-bridge.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

# 역할 생성 (이미 존재하면 무시)
if aws iam get-role --role-name $ROLE_NAME 2>/dev/null; then
    echo "✅ IAM 역할이 이미 존재합니다: $ROLE_NAME"
else
    aws iam create-role \
        --role-name $ROLE_NAME \
        --assume-role-policy-document file://trust-policy-bridge.json
    echo "✅ IAM 역할 생성 완료: $ROLE_NAME"
fi

# 정책 연결
echo "정책 연결 중..."
aws iam attach-role-policy \
    --role-name $ROLE_NAME \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true

# Bridge 권한 추가 (SQS + AgentCore)
aws iam put-role-policy \
    --role-name $ROLE_NAME \
    --policy-name BridgePolicy \
    --policy-document file://iam_policy_bridge.json

echo "✅ 정책 연결 완료"

ROLE_ARN="arn:aws:iam::$ACCOUNT_ID:role/$ROLE_NAME"
echo "Role ARN: $ROLE_ARN"

# 역할 전파 대기
echo "IAM 역할 전파 대기 중... (10초)"
sleep 10

# 2. Lambda 패키징
echo ""
echo "📦 2단계: Lambda 패키징"
rm -rf package lambda_bridge.zip

mkdir -p package
pip3 install slack-sdk boto3 -t package/ --quiet
cp lambda_bridge.py package/

cd package
zip -r ../lambda_bridge.zip . -q
cd ..

echo "✅ lambda_bridge.zip 생성 완료"
ls -lh lambda_bridge.zip

# 3. Lambda 함수 생성
echo ""
echo "📦 3단계: Lambda 함수 생성"

aws lambda create-function \
    --function-name $FUNCTION_NAME \
    --runtime python3.12 \
    --role $ROLE_ARN \
    --handler lambda_bridge.lambda_handler \
    --zip-file fileb://lambda_bridge.zip \
    --timeout 60 \
    --memory-size 256 \
    --environment "Variables={SLACK_BOT_TOKEN=$SLACK_BOT_TOKEN,AGENTCORE_RUNTIME_ARN=$AGENTCORE_RUNTIME_ARN}" \
    --region $REGION

echo "✅ Lambda 함수 생성 완료"

# 4. SQS 트리거 추가
echo ""
echo "📦 4단계: SQS 트리거 추가"

sleep 5

aws lambda create-event-source-mapping \
    --function-name $FUNCTION_NAME \
    --event-source-arn $QUEUE_ARN \
    --batch-size 1 \
    --enabled \
    --region $REGION

echo "✅ SQS 트리거 추가 완료"

# 정리
rm -f trust-policy-bridge.json

echo ""
echo "✅ 배포 완료!"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 배포된 아키텍처"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Slack → Lambda Receiver → SQS → Lambda Bridge → AgentCore"
echo ""
echo "Lambda Bridge: $FUNCTION_NAME"
echo "AgentCore ARN: $AGENTCORE_RUNTIME_ARN"
echo "SQS Queue: slack-bot-queue"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "테스트 방법:"
echo "1. Slack에서 봇에게 메시지 전송"
echo "2. CloudWatch Logs 확인:"
echo "   aws logs tail /aws/lambda/$FUNCTION_NAME --follow --region $REGION"
