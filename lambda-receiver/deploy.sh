#!/bin/bash
#
# Lambda Receiver Deployment Script
#
# Slack Bot 아키텍처에서 사용할 Lambda Receiver 함수를 생성하고 배포하는 스크립트입니다.
# Slack 이벤트를 수신하여 SQS로 전달하는 역할을 수행합니다.
#
# Usage:
#   bash deploy.sh
#
# Required Parameters (환경변수 또는 입력):
#   AWS_REGION: AWS 리전 (예: ap-northeast-2)
#   SQS_QUEUE_URL: SQS 대기열 URL
#   FUNCTION_NAME: Lambda 함수 이름 (선택사항, 기본값: slack-bot-receiver)
#

set -e

echo "🚀 Lambda Receiver 배포 시작..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 파라미터 입력
if [ -z "$AWS_REGION" ]; then
    read -p "AWS Region (예: ap-northeast-2): " AWS_REGION
fi

if [ -z "$SQS_QUEUE_URL" ]; then
    read -p "SQS Queue URL: " SQS_QUEUE_URL
fi

if [ -z "$FUNCTION_NAME" ]; then
    FUNCTION_NAME="slack-bot-receiver"
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)

echo ""
echo "📋 배포 설정:"
echo "  Function Name: $FUNCTION_NAME"
echo "  Region: $AWS_REGION"
echo "  Account ID: $ACCOUNT_ID"
echo "  SQS Queue URL: $SQS_QUEUE_URL"
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
    --policy-name SQSSendMessagePolicy \
    --policy-document file://iam_policy.json

ROLE_ARN="arn:aws:iam::$ACCOUNT_ID:role/$ROLE_NAME"
echo "  Role ARN: $ROLE_ARN"
echo "IAM 역할 전파 대기 중... (10초)"
sleep 10

# Lambda 함수 패키징
echo ""
echo "📦 2단계: Lambda 함수 패키징"
rm -rf package lambda_receiver.zip
mkdir -p package
cp lambda_receiver.py package/
cd package
zip -r ../lambda_receiver.zip . -q
cd ..
echo "  ✅ lambda_receiver.zip 생성 완료"

# Lambda 함수 생성
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
    --environment Variables={SQS_QUEUE_URL=$SQS_QUEUE_URL,AWS_REGION=$AWS_REGION} \
    --region $AWS_REGION

echo "✅ Lambda 함수 생성 완료"

FUNCTION_ARN=$(aws lambda get-function --function-name $FUNCTION_NAME --region $AWS_REGION --query 'Configuration.FunctionArn' --output text)

# API Gateway 생성
echo ""
echo "📦 4단계: API Gateway 생성"
API_NAME="${FUNCTION_NAME}-api"

API_RESPONSE=$(aws apigatewayv2 create-api \
    --name $API_NAME \
    --protocol-type HTTP \
    --target $FUNCTION_ARN \
    --region $AWS_REGION)

API_ID=$(echo $API_RESPONSE | jq -r '.ApiId')
API_ENDPOINT=$(echo $API_RESPONSE | jq -r '.ApiEndpoint')

echo "✅ API Gateway 생성 완료"
echo "  API Endpoint: $API_ENDPOINT"

# Lambda 호출 권한 추가
echo ""
echo "📦 5단계: Lambda 호출 권한 추가"
aws lambda add-permission \
    --function-name $FUNCTION_NAME \
    --statement-id apigateway-invoke \
    --action lambda:InvokeFunction \
    --principal apigateway.amazonaws.com \
    --source-arn "arn:aws:execute-api:$AWS_REGION:$ACCOUNT_ID:$API_ID/*/*" \
    --region $AWS_REGION

echo "✅ Lambda 호출 권한 추가 완료"

# 정리
rm -f trust-policy.json
echo ""
echo "✅ Lambda Receiver 배포 완료!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "🔗 Slack Event Subscriptions 설정:"
echo "  Request URL: $API_ENDPOINT"
echo ""
