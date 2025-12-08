#!/bin/bash

set -e

echo "🚀 Lambda Receiver 생성 시작..."

# 환경 변수 (기본값 설정)
FUNCTION_NAME="${FUNCTION_NAME:-slack-bot-receiver}"
REGION="${AWS_REGION:-ap-northeast-2}"
ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text 2>/dev/null)}"
QUEUE_URL="${SQS_QUEUE_URL:-https://sqs.$REGION.amazonaws.com/$ACCOUNT_ID/slack-bot-queue}"

# 1. IAM 역할 생성
echo ""
echo "📦 1단계: IAM 역할 생성"

ROLE_NAME="slack-bot-receiver-role"

# Trust Policy 생성
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

# 역할 생성 (이미 존재하면 무시)
if aws iam get-role --role-name $ROLE_NAME 2>/dev/null; then
    echo "✅ IAM 역할이 이미 존재합니다: $ROLE_NAME"
else
    aws iam create-role \
        --role-name $ROLE_NAME \
        --assume-role-policy-document file://trust-policy.json
    echo "✅ IAM 역할 생성 완료: $ROLE_NAME"
fi

# 정책 연결
echo "정책 연결 중..."
aws iam attach-role-policy \
    --role-name $ROLE_NAME \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true

# SQS 권한 추가
cat > sqs-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "sqs:SendMessage",
        "sqs:GetQueueUrl"
      ],
      "Resource": "arn:aws:sqs:$REGION:$ACCOUNT_ID:slack-bot-queue"
    }
  ]
}
EOF

# 인라인 정책 추가
aws iam put-role-policy \
    --role-name $ROLE_NAME \
    --policy-name SQSSendMessagePolicy \
    --policy-document file://sqs-policy.json

echo "✅ 정책 연결 완료"

ROLE_ARN="arn:aws:iam::$ACCOUNT_ID:role/$ROLE_NAME"
echo "Role ARN: $ROLE_ARN"

# 역할 전파 대기
echo "IAM 역할 전파 대기 중... (10초)"
sleep 10

# 2. Lambda 패키징
echo ""
echo "📦 2단계: Lambda 패키징"
rm -rf package lambda_receiver.zip
mkdir -p package

cp lambda_receiver.py package/
cd package
zip -r ../lambda_receiver.zip .
cd ..

echo "✅ lambda_receiver.zip 생성 완료"

# 3. Lambda 함수 생성
echo ""
echo "📦 3단계: Lambda 함수 생성"

aws lambda create-function \
    --function-name $FUNCTION_NAME \
    --runtime python3.11 \
    --role $ROLE_ARN \
    --handler lambda_receiver.lambda_handler \
    --zip-file fileb://lambda_receiver.zip \
    --timeout 30 \
    --memory-size 256 \
    --environment Variables={SQS_QUEUE_URL=$QUEUE_URL} \
    --region $REGION

echo "✅ Lambda 함수 생성 완료"

# 4. Lambda 함수 ARN 가져오기
FUNCTION_ARN=$(aws lambda get-function --function-name $FUNCTION_NAME --region $REGION --query 'Configuration.FunctionArn' --output text)
echo "Function ARN: $FUNCTION_ARN"

# 5. API Gateway 생성
echo ""
echo "📦 4단계: API Gateway 생성"

API_NAME="slack-bot-api"

# API 생성
API_RESPONSE=$(aws apigatewayv2 create-api \
    --name $API_NAME \
    --protocol-type HTTP \
    --target $FUNCTION_ARN \
    --region $REGION)

API_ID=$(echo $API_RESPONSE | jq -r '.ApiId')
API_ENDPOINT=$(echo $API_RESPONSE | jq -r '.ApiEndpoint')

echo "✅ API Gateway 생성 완료"
echo "API ID: $API_ID"
echo "API Endpoint: $API_ENDPOINT"

# 6. Lambda 권한 추가 (API Gateway가 Lambda를 호출할 수 있도록)
echo ""
echo "📦 5단계: Lambda 권한 추가"

aws lambda add-permission \
    --function-name $FUNCTION_NAME \
    --statement-id apigateway-invoke \
    --action lambda:InvokeFunction \
    --principal apigateway.amazonaws.com \
    --source-arn "arn:aws:execute-api:$REGION:$ACCOUNT_ID:$API_ID/*/*" \
    --region $REGION

echo "✅ Lambda 권한 추가 완료"

# 정리
rm -f trust-policy.json sqs-policy.json

echo ""
echo "✅ 배포 완료!"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 Slack Event Subscriptions 설정"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Request URL에 다음 주소를 입력하세요:"
echo "$API_ENDPOINT"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "다음 단계:"
echo "1. Slack 앱 설정 → Event Subscriptions → Request URL 입력"
echo "2. Subscribe to bot events 추가:"
echo "   - message.channels"
echo "   - message.groups"
echo "   - message.im"
echo "3. Worker Lambda 배포 요청"
