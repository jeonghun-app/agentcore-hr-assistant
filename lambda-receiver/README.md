# Lambda Receiver

Slack 이벤트를 수신하여 SQS 대기열로 전달하는 AWS Lambda 함수입니다.

## 아키텍처

```
Slack → API Gateway → Lambda Receiver → SQS
```

## 배포 방법

### 1. 파라미터 준비

다음 정보를 준비하세요:
- AWS Region (예: `ap-northeast-2`)
- SQS Queue URL (예: `https://sqs.ap-northeast-2.amazonaws.com/123456789012/slack-bot-queue`)

### 2. 배포 실행

```bash
cd lambda-receiver
bash deploy.sh
```

배포 스크립트가 다음 파라미터를 요청합니다:
- AWS Region
- SQS Queue URL
- Function Name (선택사항, 기본값: slack-bot-receiver)

### 3. Slack 설정

배포 완료 후 출력되는 API Endpoint를 Slack App 설정에 입력하세요:

1. [Slack API](https://api.slack.com/apps)에서 앱 선택
2. **Event Subscriptions** → **Enable Events**
3. **Request URL**에 API Endpoint 입력
4. **Subscribe to bot events** 추가:
   - `message.channels`
   - `message.groups`
   - `message.im`

## 환경 변수

Lambda 함수는 다음 환경 변수를 사용합니다:

- `SQS_QUEUE_URL`: SQS 대기열 URL
- `AWS_REGION`: AWS 리전

## 파일 구조

```
lambda-receiver/
├── lambda_receiver.py    # Lambda 함수 코드
├── iam_policy.json       # IAM 정책
├── deploy.sh             # 배포 스크립트
└── README.md             # 이 파일
```

## 업데이트

코드를 수정한 후 업데이트하려면:

```bash
cd lambda-receiver
zip lambda_receiver.zip lambda_receiver.py
aws lambda update-function-code \
    --function-name slack-bot-receiver \
    --zip-file fileb://lambda_receiver.zip \
    --region ap-northeast-2
```
