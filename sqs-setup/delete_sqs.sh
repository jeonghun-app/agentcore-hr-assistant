#!/bin/bash
# SQS Queue Deletion Script
# SQS 대기열을 삭제합니다.

set -e

echo "=== SQS Queue Deletion ==="
echo ""

# sqs_config.json에서 설정 읽기
if [ -f "sqs_config.json" ]; then
    echo "Found sqs_config.json"
    QUEUE_URL=$(jq -r '.queue_url' sqs_config.json)
    DLQ_URL=$(jq -r '.dlq_url' sqs_config.json)
    AWS_REGION=$(jq -r '.region' sqs_config.json)
    QUEUE_NAME=$(jq -r '.queue_name' sqs_config.json)
    
    echo "  Queue Name: $QUEUE_NAME"
    echo "  Queue URL: $QUEUE_URL"
    echo "  Region: $AWS_REGION"
    if [ -n "$DLQ_URL" ] && [ "$DLQ_URL" != "null" ]; then
        echo "  DLQ URL: $DLQ_URL"
    fi
    echo ""
else
    # 수동 입력
    read -p "Enter Queue URL: " QUEUE_URL
    read -p "Enter AWS Region [ap-northeast-2]: " AWS_REGION
    AWS_REGION=${AWS_REGION:-ap-northeast-2}
    
    read -p "Enter DLQ URL (optional, press Enter to skip): " DLQ_URL
fi

# 확인
echo ""
echo "⚠️  WARNING: This will permanently delete the SQS queue(s)!"
echo ""
read -p "Are you sure you want to delete? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Deletion cancelled."
    exit 0
fi

# Main Queue 삭제
echo ""
echo "Deleting main queue..."
aws sqs delete-queue \
    --queue-url "$QUEUE_URL" \
    --region "$AWS_REGION"

if [ $? -eq 0 ]; then
    echo "✓ Main queue deleted successfully"
else
    echo "✗ Failed to delete main queue"
fi

# DLQ 삭제
if [ -n "$DLQ_URL" ] && [ "$DLQ_URL" != "null" ]; then
    echo ""
    echo "Deleting Dead Letter Queue..."
    aws sqs delete-queue \
        --queue-url "$DLQ_URL" \
        --region "$AWS_REGION"
    
    if [ $? -eq 0 ]; then
        echo "✓ DLQ deleted successfully"
    else
        echo "✗ Failed to delete DLQ"
    fi
fi

# 설정 파일 삭제
if [ -f "sqs_config.json" ]; then
    read -p "Delete sqs_config.json? (Y/n): " DELETE_CONFIG
    DELETE_CONFIG=${DELETE_CONFIG:-Y}
    
    if [[ "$DELETE_CONFIG" =~ ^[Yy]$ ]]; then
        rm -f sqs_config.json
        echo "✓ sqs_config.json deleted"
    fi
fi

echo ""
echo "=== SQS Queue Deletion Complete ==="
