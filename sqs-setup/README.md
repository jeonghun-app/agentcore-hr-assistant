# SQS Setup

Slack Bot을 위한 SQS 대기열을 생성하는 스크립트입니다.

## 아키텍처

```
Slack → API Gateway → Lambda Receiver → SQS → Lambda Bridge → AgentCore
```

SQS는 Lambda Receiver와 Lambda Bridge 사이에서 메시지 큐 역할을 합니다:
- **비동기 처리**: Slack의 3초 타임아웃 제한 회피
- **안정성**: 메시지 손실 방지 및 재시도 메커니즘
- **확장성**: 트래픽 급증 시 버퍼 역할

## 배포 순서

전체 시스템을 배포하려면 다음 순서를 따르세요:

1. **SQS 생성** (이 폴더)
2. Lambda Receiver 배포
3. Lambda Bridge 배포
4. AgentCore 배포

## SQS 생성 방법

### 1. 스크립트 실행

```bash
cd sqs-setup
bash create_sqs.sh
```

### 2. 파라미터 입력

스크립트가 다음 정보를 요청합니다:

- **Queue Name**: SQS 대기열 이름 (기본값: `slack-bot-queue`)
- **AWS Region**: AWS 리전 (기본값: `ap-northeast-2`)
- **Visibility Timeout**: 메시지 처리 시간 (기본값: 300초 = 5분)
- **Message Retention**: 메시지 보관 기간 (기본값: 345600초 = 4일)
- **Create DLQ**: Dead Letter Queue 생성 여부 (기본값: Y)

### 3. 출력 정보

스크립트 실행 후 다음 정보가 출력됩니다:

```
Queue URL: https://sqs.ap-northeast-2.amazonaws.com/123456789012/slack-bot-queue
Queue ARN: arn:aws:sqs:ap-northeast-2:123456789012:slack-bot-queue
```

이 정보는 `sqs_config.json` 파일에도 저장됩니다.

## SQS 설정 상세

### Visibility Timeout (가시성 타임아웃)

- **기본값**: 300초 (5분)
- **설명**: Lambda가 메시지를 처리하는 동안 다른 컨슈머가 해당 메시지를 볼 수 없는 시간
- **권장값**: Lambda 함수의 최대 실행 시간보다 길게 설정

### Message Retention Period (메시지 보관 기간)

- **기본값**: 345600초 (4일)
- **설명**: 처리되지 않은 메시지를 SQS에 보관하는 기간
- **범위**: 60초 ~ 1209600초 (14일)

### Dead Letter Queue (DLQ)

- **목적**: 처리 실패한 메시지를 별도로 보관
- **설정**: 3회 재시도 후 DLQ로 이동
- **보관 기간**: 14일

## 생성된 파일

### sqs_config.json

SQS 설정 정보가 저장된 JSON 파일:

```json
{
  "queue_name": "slack-bot-queue",
  "queue_url": "https://sqs.ap-northeast-2.amazonaws.com/123456789012/slack-bot-queue",
  "queue_arn": "arn:aws:sqs:ap-northeast-2:123456789012:slack-bot-queue",
  "region": "ap-northeast-2",
  "dlq_url": "https://sqs.ap-northeast-2.amazonaws.com/123456789012/slack-bot-queue-dlq",
  "dlq_arn": "arn:aws:sqs:ap-northeast-2:123456789012:slack-bot-queue-dlq"
}
```

## 다음 단계

SQS 생성 후:

1. **Lambda Receiver 배포**
   ```bash
   cd ../lambda-receiver
   bash deploy.sh
   ```
   - SQS Queue URL 입력 필요

2. **Lambda Bridge 배포**
   ```bash
   cd ../lambda-bridge
   bash deploy.sh
   ```
   - SQS Queue ARN 입력 필요

## 모니터링

### CloudWatch 메트릭

SQS는 자동으로 다음 메트릭을 CloudWatch에 전송합니다:

- `ApproximateNumberOfMessagesVisible`: 대기 중인 메시지 수
- `ApproximateNumberOfMessagesNotVisible`: 처리 중인 메시지 수
- `NumberOfMessagesSent`: 전송된 메시지 수
- `NumberOfMessagesReceived`: 수신된 메시지 수
- `NumberOfMessagesDeleted`: 삭제된 메시지 수

### 메시지 확인

```bash
# 대기 중인 메시지 수 확인
aws sqs get-queue-attributes \
    --queue-url <QUEUE_URL> \
    --attribute-names ApproximateNumberOfMessages \
    --region ap-northeast-2

# DLQ 메시지 확인
aws sqs receive-message \
    --queue-url <DLQ_URL> \
    --max-number-of-messages 10 \
    --region ap-northeast-2
```

## 삭제

SQS 대기열을 삭제하려면:

```bash
# Main Queue 삭제
aws sqs delete-queue \
    --queue-url <QUEUE_URL> \
    --region ap-northeast-2

# DLQ 삭제
aws sqs delete-queue \
    --queue-url <DLQ_URL> \
    --region ap-northeast-2
```

## 문제 해결

### 메시지가 DLQ로 이동하는 경우

1. Lambda Bridge 로그 확인:
   ```bash
   aws logs tail /aws/lambda/slack-bot-bridge --follow --region ap-northeast-2
   ```

2. DLQ 메시지 확인:
   ```bash
   aws sqs receive-message --queue-url <DLQ_URL> --region ap-northeast-2
   ```

3. 원인 파악 후 DLQ 메시지를 Main Queue로 재전송:
   ```bash
   # DLQ에서 메시지 읽기
   aws sqs receive-message --queue-url <DLQ_URL> --region ap-northeast-2
   
   # Main Queue로 재전송
   aws sqs send-message --queue-url <QUEUE_URL> --message-body "<MESSAGE>" --region ap-northeast-2
   ```

### 메시지가 쌓이는 경우

- Lambda Bridge의 동시 실행 수 확인
- Lambda 함수의 타임아웃 설정 확인
- AgentCore Runtime 상태 확인

## 비용

SQS 요금 (2025년 기준):

- **무료 티어**: 월 100만 요청
- **추가 요청**: 100만 요청당 $0.40
- **데이터 전송**: 무료 (같은 리전 내)

일반적인 Slack Bot 사용량에서는 무료 티어 내에서 충분히 사용 가능합니다.
