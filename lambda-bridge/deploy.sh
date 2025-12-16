#!/bin/bash
#
# Lambda Bridge Deployment Script
#
# SQS 대기열에서 메시지를 수신하여 AWS Bedrock AgentCore Runtime으로 전달하고,
# 처리 결과를 Slack 채널로 전송하는 Lambda Bridge 함수를 배포하는 스크립트입니다.
#
# Usage:
#   bash deploy.sh
#
# Required Parameters (환경변수 또는 입력):
#   AWS_REGION: AWS 리전 (예: ap-northeast-2)
#   SLACK_BOT_TOKEN: Slack Bot Token (xoxb-로 시작)
#   AGENTCORE_RUNTIME_ARN: AgentCore Runtime ARN
#   AGENTCORE_REGION: AgentCore Runtime 리전 (예: us-east-1)
#   SQS_QUEUE_ARN: SQS Queue ARN
#

set -e

echo "🚀 Lambda Bridge 배포 시작..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 파라미터 입력
if [ -z "$AWS_REGION" ]; then
    read -p "AWS Region (예: ap-northeast-2): " AWS_REGION
fi

if [ -z "$SLACK_BOT_TOKEN" ]; then
    read -p "Slack Bot Token (xoxb-로 시작): " SLACK_BOT_TOKEN
fi

if [ -z "$AGENTCORE_RUNTIME_ARN" ]; then
    echo ""
    echo "AgentCore Runtime ARN을 가져오는 방법:"
    echo "  1. agentcore status --agent <agent-name> --verbose | grep agent_arn"
    echo "  2. 또는 직접 입력"
    echo ""
    read -p "AgentCore Runtime ARN: " AGENTCORE_RUNTIME_ARN
    
    # ARN 형식 검증
    if [[ ! "$AGENTCORE_RUNTIME_ARN" =~ ^arn:aws:bedrock-agentcore: ]]; then
        echo "Warning: ARN이 올바른 형식이 아닐 수 있습니다."
        echo "Expected format: arn:aws:bedrock-agentcore:region:account:runtime/agent-name-xxxxx"
    fi
fi

if [ -z "$AGENTCORE_REGION" ]; then
    read -p "AgentCore Region (예: us-east-1): " AGENTCORE_REGION
fi

if [ -z "$SQS_QUEUE_ARN" ]; then
    read -p "SQS Queue ARN: " SQS_QUEUE_ARN
fi

if [ -z "$FUNCTION_NAME" ]; then
    FUNCTION_NAME="slack-bot-bridge"
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)

echo ""
echo "📋 배포 설정:"
echo "  Function Name: $FUNCTION_NAME"
echo "  Region: $AWS_REGION"
echo "  Account ID: $ACCOUNT_ID"
echo "  AgentCore ARN: $AGENTCORE_RUNTIME_ARN"
echo "  AgentCore Region: $AGENTCORE_REGION"
echo "  SQS Queue ARN: $SQS_QUEUE_ARN"
echo ""

# IAM 역할 생성
echo "📦 1단계: IAM 역할 생성"
ROLE_NAME="${FUNCTION_NAME}-role"

cat > trust-policy.json <<EOF
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

if aws iam get-role --role-name $ROLE_NAME 2>/dev/null; then
    echo "✅ IAM 역할이 이미 존재합니다: $ROLE_NAME"
else
    aws iam create-role \
        --role-name $ROLE_NAME \
        --assume-role-policy-document file://trust-policy.json
    echo "✅ IAM 역할 생성 완료: $ROLE_NAME"
fi

aws iam attach-role-policy \
    --role-name $ROLE_NAME \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true

aws iam put-role-policy \
    --role-name $ROLE_NAME \
    --policy-name BridgePolicy \
    --policy-document file://iam_policy.json

ROLE_ARN="arn:aws:iam::$ACCOUNT_ID:role/$ROLE_NAME"
echo "  Role ARN: $ROLE_ARN"
echo "IAM 역할 전파 대기 중... (10초)"
sleep 10

# Lambda 함수 패키징
echo ""
echo "📦 2단계: Lambda 함수 패키징"
rm -rf package lambda_bridge.zip
mkdir -p package

echo "Python 의존성 설치 중..."
pip3 install -r requirements.txt -t package/ --quiet

cp lambda_bridge.py package/
cd package
zip -r ../lambda_bridge.zip . -q
cd ..
echo "✅ lambda_bridge.zip 생성 완료"

# Lambda 함수 생성
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
    --environment "Variables={SLACK_BOT_TOKEN=$SLACK_BOT_TOKEN,AGENTCORE_RUNTIME_ARN=$AGENTCORE_RUNTIME_ARN,AGENTCORE_REGION=$AGENTCORE_REGION}" \
    --region $AWS_REGION

echo "✅ Lambda 함수 생성 완료"

# SQS 트리거 연결
echo ""
echo "📦 4단계: SQS 트리거 연결"
echo "Lambda 함수 준비 대기 중... (5초)"
sleep 5

aws lambda create-event-source-mapping \
    --function-name $FUNCTION_NAME \
    --event-source-arn $SQS_QUEUE_ARN \
    --batch-size 1 \
    --maximum-batching-window-in-seconds 0 \
    --enabled \
    --region $AWS_REGION

echo "✅ SQS 트리거 연결 완료"

# 정리
rm -f trust-policy.json
echo ""
echo "✅ Lambda Bridge 배포 완료!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
