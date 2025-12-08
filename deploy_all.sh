#!/bin/bash

set -e

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 Slack Bot with AgentCore Runtime 통합 배포"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 환경 변수
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text 2>/dev/null)"
REGION_SQS="${AWS_REGION:-ap-northeast-2}"
REGION_AGENTCORE="${AGENTCORE_REGION:-us-east-1}"

# 사용자 입력
echo "📝 설정 정보 입력"
echo ""
read -p "Knowledge Base ID: " KNOWLEDGE_BASE_ID
read -p "Knowledge Base 모델 ARN (ap-northeast-2): " KB_MODEL_ARN
read -p "AgentCore 모델 ARN (us-east-1): " AGENTCORE_MODEL_ARN
read -p "Slack Bot Token (xoxb-로 시작): " SLACK_BOT_TOKEN

if [ -z "$KNOWLEDGE_BASE_ID" ] || [ -z "$KB_MODEL_ARN" ] || [ -z "$AGENTCORE_MODEL_ARN" ] || [ -z "$SLACK_BOT_TOKEN" ]; then
    echo "❌ 모든 정보를 입력해야 합니다"
    exit 1
fi

echo ""
echo "✅ 설정 확인:"
echo "  Knowledge Base ID: $KNOWLEDGE_BASE_ID"
echo "  KB Model: $KB_MODEL_ARN"
echo "  AgentCore Model: $AGENTCORE_MODEL_ARN"
echo "  Slack Token: ${SLACK_BOT_TOKEN:0:20}..."
echo ""
read -p "계속하시겠습니까? (y/n): " CONFIRM

if [ "$CONFIRM" != "y" ]; then
    echo "배포 취소"
    exit 0
fi

# agentcore_worker_http.py 업데이트
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📝 AgentCore Worker 설정 업데이트"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

sed -i "s|KNOWLEDGE_BASE_ID = '.*'|KNOWLEDGE_BASE_ID = '$KNOWLEDGE_BASE_ID'|" agentcore_worker_http.py
sed -i "s|'modelArn': 'arn:aws:bedrock:ap-northeast-2:.*'|'modelArn': '$KB_MODEL_ARN'|" agentcore_worker_http.py
sed -i "s|model=\"arn:aws:bedrock:us-east-1:.*\"|model=\"$AGENTCORE_MODEL_ARN\"|" agentcore_worker_http.py

echo "✅ Worker 설정 완료"

# 1. SQS 생성
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📦 1단계: SQS Queue 생성"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

python3 create_sqs_queue.py
SQS_QUEUE_URL=$(aws sqs get-queue-url --queue-name slack-bot-queue --region $REGION_SQS --query 'QueueUrl' --output text)
SQS_QUEUE_ARN="arn:aws:sqs:$REGION_SQS:$ACCOUNT_ID:slack-bot-queue"

echo "✅ SQS Queue 생성 완료"
echo "  URL: $SQS_QUEUE_URL"
echo "  ARN: $SQS_QUEUE_ARN"

# 2. Lambda Receiver 생성
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📦 2단계: Lambda Receiver 생성"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

bash create_lambda_receiver.sh

echo "✅ Lambda Receiver 생성 완료"

# 3. API Gateway 생성 및 연결
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📦 3단계: API Gateway 생성"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# API Gateway 생성
API_ID=$(aws apigatewayv2 create-api \
    --name slack-bot-api \
    --protocol-type HTTP \
    --region $REGION_SQS \
    --query 'ApiId' \
    --output text 2>/dev/null || \
    aws apigatewayv2 get-apis --region $REGION_SQS --query "Items[?Name=='slack-bot-api'].ApiId" --output text)

echo "API Gateway ID: $API_ID"

# Lambda 통합 생성
LAMBDA_ARN="arn:aws:lambda:$REGION_SQS:$ACCOUNT_ID:function:slack-bot-receiver"

INTEGRATION_ID=$(aws apigatewayv2 create-integration \
    --api-id $API_ID \
    --integration-type AWS_PROXY \
    --integration-uri $LAMBDA_ARN \
    --payload-format-version 2.0 \
    --region $REGION_SQS \
    --query 'IntegrationId' \
    --output text 2>/dev/null || \
    aws apigatewayv2 get-integrations --api-id $API_ID --region $REGION_SQS --query 'Items[0].IntegrationId' --output text)

echo "Integration ID: $INTEGRATION_ID"

# Route 생성
aws apigatewayv2 create-route \
    --api-id $API_ID \
    --route-key 'POST /slack/events' \
    --target integrations/$INTEGRATION_ID \
    --region $REGION_SQS 2>/dev/null || echo "Route already exists"

# Stage 생성
aws apigatewayv2 create-stage \
    --api-id $API_ID \
    --stage-name prod \
    --auto-deploy \
    --region $REGION_SQS 2>/dev/null || echo "Stage already exists"

# Lambda 권한 추가
aws lambda add-permission \
    --function-name slack-bot-receiver \
    --statement-id apigateway-invoke \
    --action lambda:InvokeFunction \
    --principal apigateway.amazonaws.com \
    --source-arn "arn:aws:execute-api:$REGION_SQS:$ACCOUNT_ID:$API_ID/*/*/slack/events" \
    --region $REGION_SQS 2>/dev/null || echo "Permission already exists"

API_ENDPOINT="https://$API_ID.execute-api.$REGION_SQS.amazonaws.com/prod/slack/events"

echo "✅ API Gateway 생성 완료"
echo "  Endpoint: $API_ENDPOINT"

# 4. AgentCore 배포
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📦 4단계: AgentCore Runtime 배포"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

bash deploy_agentcore.sh

AGENTCORE_ARN=$(cat agentcore_arn.txt)
echo "✅ AgentCore 배포 완료"
echo "  ARN: $AGENTCORE_ARN"

# 5. Lambda Bridge 생성
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📦 5단계: Lambda Bridge 생성"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# IAM Role 생성
BRIDGE_ROLE_NAME="slack-bot-bridge-role"

cat > trust-policy-bridge.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Service": "lambda.amazonaws.com"},
    "Action": "sts:AssumeRole"
  }]
}
EOF

if ! aws iam get-role --role-name $BRIDGE_ROLE_NAME 2>/dev/null; then
    aws iam create-role \
        --role-name $BRIDGE_ROLE_NAME \
        --assume-role-policy-document file://trust-policy-bridge.json
    echo "✅ IAM 역할 생성"
else
    echo "✅ IAM 역할 존재"
fi

aws iam attach-role-policy \
    --role-name $BRIDGE_ROLE_NAME \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true

aws iam put-role-policy \
    --role-name $BRIDGE_ROLE_NAME \
    --policy-name BridgePolicy \
    --policy-document file://iam_policy_bridge.json

BRIDGE_ROLE_ARN="arn:aws:iam::$ACCOUNT_ID:role/$BRIDGE_ROLE_NAME"

echo "IAM 역할 전파 대기... (10초)"
sleep 10

# Lambda 패키징
rm -rf package lambda_bridge.zip
mkdir -p package
pip3 install slack-sdk boto3 -t package/ --quiet
cp lambda_bridge.py package/
cd package && zip -r ../lambda_bridge.zip . -q && cd ..

# Lambda 함수 생성 또는 업데이트
if aws lambda get-function --function-name slack-bot-bridge --region $REGION_SQS 2>/dev/null; then
    aws lambda update-function-code \
        --function-name slack-bot-bridge \
        --zip-file fileb://lambda_bridge.zip \
        --region $REGION_SQS > /dev/null
    
    aws lambda update-function-configuration \
        --function-name slack-bot-bridge \
        --environment "Variables={SLACK_BOT_TOKEN=$SLACK_BOT_TOKEN,AGENTCORE_RUNTIME_ARN=$AGENTCORE_ARN}" \
        --region $REGION_SQS > /dev/null
    
    echo "✅ Lambda Bridge 업데이트"
else
    aws lambda create-function \
        --function-name slack-bot-bridge \
        --runtime python3.12 \
        --role $BRIDGE_ROLE_ARN \
        --handler lambda_bridge.lambda_handler \
        --zip-file fileb://lambda_bridge.zip \
        --timeout 60 \
        --memory-size 256 \
        --environment "Variables={SLACK_BOT_TOKEN=$SLACK_BOT_TOKEN,AGENTCORE_RUNTIME_ARN=$AGENTCORE_ARN}" \
        --region $REGION_SQS > /dev/null
    
    echo "✅ Lambda Bridge 생성"
fi

sleep 5

# SQS 트리거 추가
if ! aws lambda list-event-source-mappings \
    --function-name slack-bot-bridge \
    --region $REGION_SQS \
    --query 'EventSourceMappings[0].UUID' \
    --output text 2>/dev/null | grep -q '^[a-f0-9-]*$'; then
    
    aws lambda create-event-source-mapping \
        --function-name slack-bot-bridge \
        --event-source-arn $SQS_QUEUE_ARN \
        --batch-size 1 \
        --enabled \
        --region $REGION_SQS > /dev/null
    
    echo "✅ SQS 트리거 추가"
else
    echo "✅ SQS 트리거 존재"
fi

# 정리
rm -f trust-policy-bridge.json

# 완료
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎉 배포 완료!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📋 배포된 아키텍처:"
echo ""
echo "  Slack → API Gateway → Lambda Receiver → SQS"
echo "                                            ↓"
echo "                          Lambda Bridge → AgentCore Runtime"
echo "                                ↓"
echo "                              Slack"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📌 리소스 정보:"
echo ""
echo "  API Gateway Endpoint:"
echo "    $API_ENDPOINT"
echo ""
echo "  SQS Queue:"
echo "    $SQS_QUEUE_URL"
echo ""
echo "  AgentCore Runtime:"
echo "    $AGENTCORE_ARN"
echo ""
echo "  Lambda Functions:"
echo "    - slack-bot-receiver ($REGION_SQS)"
echo "    - slack-bot-bridge ($REGION_SQS)"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "🔧 다음 단계:"
echo ""
echo "  1. Slack App 설정 (https://api.slack.com/apps)"
echo "     - Event Subscriptions → Request URL:"
echo "       $API_ENDPOINT"
echo ""
echo "  2. Bot Token Scopes 확인:"
echo "     - channels:history"
echo "     - chat:write"
echo "     - groups:history"
echo "     - im:history"
echo ""
echo "  3. Slack에서 봇 테스트:"
echo "     - \"안녕\" 또는 \"100 곱하기 50은?\""
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
