#!/bin/bash
# SQS Queue Creation Script for Slack Bot
# Slack 이벤트 처리를 위한 SQS 대기열을 생성합니다.

set -e

echo "=== SQS Queue Setup for Slack Bot ==="
echo ""

# AWS Profile 선택
echo "Available AWS Profiles:"
aws configure list-profiles
echo ""
read -p "Enter AWS Profile to use [default]: " AWS_PROFILE
AWS_PROFILE=${AWS_PROFILE:-default}
export AWS_PROFILE
echo "✓ Using AWS Profile: $AWS_PROFILE"
echo ""

# 기본값 설정
DEFAULT_QUEUE_NAME="slack-bot-queue"
DEFAULT_REGION="ap-northeast-2"
DEFAULT_VISIBILITY_TIMEOUT="300"  # 5분 (Lambda 처리 시간 고려)
DEFAULT_MESSAGE_RETENTION="345600"  # 4일
DEFAULT_RECEIVE_WAIT_TIME="20"  # Long polling

# 파라미터 입력
read -p "Enter Queue Name [$DEFAULT_QUEUE_NAME]: " QUEUE_NAME
QUEUE_NAME=${QUEUE_NAME:-$DEFAULT_QUEUE_NAME}

read -p "Enter AWS Region [$DEFAULT_REGION]: " AWS_REGION
AWS_REGION=${AWS_REGION:-$DEFAULT_REGION}

read -p "Enter Visibility Timeout (seconds) [$DEFAULT_VISIBILITY_TIMEOUT]: " VISIBILITY_TIMEOUT
VISIBILITY_TIMEOUT=${VISIBILITY_TIMEOUT:-$DEFAULT_VISIBILITY_TIMEOUT}

read -p "Enter Message Retention Period (seconds) [$DEFAULT_MESSAGE_RETENTION]: " MESSAGE_RETENTION
MESSAGE_RETENTION=${MESSAGE_RETENTION:-$DEFAULT_MESSAGE_RETENTION}

RECEIVE_WAIT_TIME=${DEFAULT_RECEIVE_WAIT_TIME}

echo ""
echo "=== Configuration ==="
echo "  Queue Name: $QUEUE_NAME"
echo "  Region: $AWS_REGION"
echo "  Visibility Timeout: $VISIBILITY_TIMEOUT seconds"
echo "  Message Retention: $MESSAGE_RETENTION seconds"
echo ""

# SQS 대기열 생성
echo "Creating SQS queue..."
QUEUE_URL=$(aws sqs create-queue \
    --profile "$AWS_PROFILE" \
    --queue-name "$QUEUE_NAME" \
    --region "$AWS_REGION" \
    --attributes "{
        \"VisibilityTimeout\": \"$VISIBILITY_TIMEOUT\",
        \"MessageRetentionPeriod\": \"$MESSAGE_RETENTION\",
        \"ReceiveMessageWaitTimeSeconds\": \"$RECEIVE_WAIT_TIME\",
        \"DelaySeconds\": \"0\"
    }" \
    --query 'QueueUrl' \
    --output text 2>&1)

if [ $? -ne 0 ]; then
    # 이미 존재하는 경우 URL 가져오기
    if echo "$QUEUE_URL" | grep -q "QueueAlreadyExists"; then
        echo "Queue already exists. Getting queue URL..."
        QUEUE_URL=$(aws sqs get-queue-url \
            --profile "$AWS_PROFILE" \
            --queue-name "$QUEUE_NAME" \
            --region "$AWS_REGION" \
            --query 'QueueUrl' \
            --output text)
        echo "✓ Using existing queue"
    else
        echo "Error creating queue: $QUEUE_URL"
        exit 1
    fi
else
    echo "✓ Queue created successfully"
fi

# Queue ARN 가져오기
echo ""
echo "Getting queue attributes..."
QUEUE_ARN=$(aws sqs get-queue-attributes \
    --profile "$AWS_PROFILE" \
    --queue-url "$QUEUE_URL" \
    --attribute-names QueueArn \
    --region "$AWS_REGION" \
    --query 'Attributes.QueueArn' \
    --output text)

echo "✓ Queue attributes retrieved"
echo ""

# Dead Letter Queue 생성 여부 확인
read -p "Create Dead Letter Queue for failed messages? (Y/n): " CREATE_DLQ
CREATE_DLQ=${CREATE_DLQ:-Y}

if [[ "$CREATE_DLQ" =~ ^[Yy]$ ]]; then
    DLQ_NAME="${QUEUE_NAME}-dlq"
    echo ""
    echo "Creating Dead Letter Queue: $DLQ_NAME"
    
    DLQ_URL=$(aws sqs create-queue \
        --profile "$AWS_PROFILE" \
        --queue-name "$DLQ_NAME" \
        --region "$AWS_REGION" \
        --attributes "{
            \"MessageRetentionPeriod\": \"1209600\"
        }" \
        --query 'QueueUrl' \
        --output text 2>&1)
    
    if [ $? -ne 0 ]; then
        if echo "$DLQ_URL" | grep -q "QueueAlreadyExists"; then
            echo "DLQ already exists. Getting queue URL..."
            DLQ_URL=$(aws sqs get-queue-url \
                --profile "$AWS_PROFILE" \
                --queue-name "$DLQ_NAME" \
                --region "$AWS_REGION" \
                --query 'QueueUrl' \
                --output text)
        else
            echo "Warning: Failed to create DLQ: $DLQ_URL"
            DLQ_URL=""
        fi
    fi
    
    if [ -n "$DLQ_URL" ]; then
        # DLQ ARN 가져오기
        DLQ_ARN=$(aws sqs get-queue-attributes \
            --profile "$AWS_PROFILE" \
            --queue-url "$DLQ_URL" \
            --attribute-names QueueArn \
            --region "$AWS_REGION" \
            --query 'Attributes.QueueArn' \
            --output text)
        
        # Redrive Policy 설정
        echo "Configuring redrive policy..."
        aws sqs set-queue-attributes \
            --profile "$AWS_PROFILE" \
            --queue-url "$QUEUE_URL" \
            --attributes "{
                \"RedrivePolicy\": \"{\\\"deadLetterTargetArn\\\":\\\"$DLQ_ARN\\\",\\\"maxReceiveCount\\\":\\\"3\\\"}\"
            }" \
            --region "$AWS_REGION"
        
        echo "✓ Dead Letter Queue configured"
        echo "  DLQ URL: $DLQ_URL"
        echo "  DLQ ARN: $DLQ_ARN"
    fi
fi

# 결과 출력 및 저장
echo ""
echo "=== SQS Queue Created Successfully! ==="
echo ""
echo "Queue Information:"
echo "  Queue Name: $QUEUE_NAME"
echo "  Queue URL: $QUEUE_URL"
echo "  Queue ARN: $QUEUE_ARN"
echo "  Region: $AWS_REGION"
echo ""

# 설정 파일 저장
cat > sqs_config.json <<EOF
{
  "queue_name": "$QUEUE_NAME",
  "queue_url": "$QUEUE_URL",
  "queue_arn": "$QUEUE_ARN",
  "region": "$AWS_REGION",
  "dlq_url": "${DLQ_URL:-}",
  "dlq_arn": "${DLQ_ARN:-}"
}
EOF

echo "✓ Configuration saved to sqs_config.json"
echo ""

# 다음 단계 안내
echo "=== Next Steps ==="
echo ""
echo "1. Lambda Receiver 배포 시 사용할 값:"
echo "   SQS_QUEUE_URL=$QUEUE_URL"
echo ""
echo "2. Lambda Bridge 배포 시 사용할 값:"
echo "   SQS_QUEUE_ARN=$QUEUE_ARN"
echo ""
echo "3. Lambda Receiver 배포:"
echo "   cd ../lambda-receiver"
echo "   bash deploy.sh"
echo ""
echo "4. Lambda Bridge 배포:"
echo "   cd ../lambda-bridge"
echo "   bash deploy.sh"
echo ""
echo "Configuration file: $(pwd)/sqs_config.json"
