# Lambda Bridge

SQS 대기열에서 메시지를 수신하여 AWS Bedrock AgentCore Runtime으로 전달하고,
처리 결과를 Slack 채널로 전송하는 AWS Lambda 함수입니다.

## 아키텍처

```
SQS → Lambda Bridge → AgentCore Runtime → Slack Response
```

## 배포 방법

### 1. 파라미터 준비

다음 정보를 준비하세요:
- AWS Region (예: `ap-northeast-2`)
- Slack Bot Token (xoxb-로 시작)
- AgentCore Runtime ARN
- AgentCore Region (예: `us-east-1`)
- SQS Queue ARN

### 2. 배포 실행

```bash
cd lambda-bridge
bash deploy.sh
```

배포 스크립트가 다음 파라미터를 요청합니다:
- AWS Region
- Slack Bot Token
- AgentCore Runtime ARN (아래 명령어로 확인)
  ```bash
  agentcore status --agent hr_assistant_agent --verbose | grep agent_arn
  ```
- AgentCore Region
- SQS Queue ARN
- Function Name (선택사항, 기본값: slack-bot-bridge)

## 환경 변수

Lambda 함수는 다음 환경 변수를 사용합니다:

- `SLACK_BOT_TOKEN`: Slack Bot Token
- `AGENTCORE_RUNTIME_ARN`: AgentCore Runtime ARN
  - 형식: `arn:aws:bedrock-agentcore:us-east-1:123456789012:runtime/agent_name-xxxxx`
  - 확인: `agentcore status --agent <agent-name> --verbose | grep agent_arn`
- `AGENTCORE_REGION`: AgentCore Runtime 리전

## 파일 구조

```
lambda-bridge/
├── lambda_bridge.py      # Lambda 함수 코드
├── iam_policy.json       # IAM 정책
├── requirements.txt      # Python 의존성
├── deploy.sh             # 배포 스크립트
└── README.md             # 이 파일
```

## 업데이트

### 코드 업데이트

코드를 수정한 후:

```bash
cd lambda-bridge
bash deploy.sh
```

기존 Lambda 함수가 자동으로 업데이트됩니다.

### 환경 변수만 업데이트

AgentCore Runtime ARN이 변경된 경우:

```bash
aws lambda update-function-configuration \
    --function-name slack-bot-bridge \
    --environment "Variables={SLACK_BOT_TOKEN=$SLACK_BOT_TOKEN,AGENTCORE_RUNTIME_ARN=$NEW_ARN,AGENTCORE_REGION=us-east-1}" \
    --region ap-northeast-2
```

### 수동 코드 업데이트

```bash
cd lambda-bridge
pip3 install -r requirements.txt -t package/
cp lambda_bridge.py package/
cd package && zip -r ../lambda_bridge.zip . && cd ..
aws lambda update-function-code \
    --function-name slack-bot-bridge \
    --zip-file fileb://lambda_bridge.zip \
    --region ap-northeast-2
```
