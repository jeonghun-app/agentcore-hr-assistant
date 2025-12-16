# Slack Bot with AWS Bedrock AgentCore

Slack Bot과 AWS Bedrock AgentCore Runtime을 연동한 AI 어시스턴트 시스템입니다.

## 아키텍처

```
Slack → API Gateway → Lambda Receiver → SQS → Lambda Bridge → AgentCore Runtime
```

## 프로젝트 구조

```
.
├── lambda-receiver/          # Slack 이벤트 수신 Lambda
│   ├── lambda_receiver.py
│   ├── iam_policy.json
│   ├── deploy.sh
│   └── README.md
│
├── lambda-bridge/            # SQS → AgentCore 브릿지 Lambda
│   ├── lambda_bridge.py
│   ├── iam_policy.json
│   ├── requirements.txt
│   ├── deploy.sh
│   └── README.md
│
├── agentcore/                # AgentCore Runtime 애플리케이션
│   ├── agentcore_worker_http.py
│   ├── requirements.txt
│   ├── deploy.sh
│   └── README.md
│
└── README.md                 # 이 파일
```

## 배포 순서

### 1. AgentCore Runtime 배포

AgentCore CLI를 사용하여 코드를 직접 배포합니다 (Docker 불필요).

```bash
cd agentcore
bash deploy.sh
```

입력 정보:
- Agent Name (기본값: hr_assistant_agent)
  - 주의: 하이픈(-) 사용 불가, 언더스코어(_)만 가능
- AWS Region (기본값: us-east-1)
- Python Runtime (기본값: PYTHON_3_13)
- Knowledge Base ID (선택사항)
- KB Region (기본값: us-east-1)

배포 완료 후 Agent ARN을 기록해두세요:
```bash
agentcore status --agent hr_assistant_agent --verbose | grep agent_arn
```

자세한 내용은 [AgentCore README](agentcore/README.md)를 참조하세요.

### 2. Lambda Receiver 배포

Slack 이벤트를 수신하고 SQS로 전달하는 Lambda를 배포합니다.

```bash
cd lambda-receiver
bash deploy.sh
```

입력 정보:
- AWS Region (예: ap-northeast-2)

배포 완료 후:
- SQS Queue URL 기록
- API Gateway Endpoint를 Slack App 설정에 입력

자세한 내용은 [Lambda Receiver README](lambda-receiver/README.md)를 참조하세요.

### 3. Lambda Bridge 배포

SQS 메시지를 받아 AgentCore Runtime을 호출하는 Lambda를 배포합니다.

```bash
cd lambda-bridge
bash deploy.sh
```

입력 정보:
- AWS Region (예: ap-northeast-2)
- Slack Bot Token (xoxb-로 시작)
- AgentCore Runtime ARN (1단계에서 기록)
  ```bash
  agentcore status --agent hr_assistant_agent --verbose | grep agent_arn
  ```
- AgentCore Region (예: us-east-1)
- SQS Queue ARN (2단계에서 기록)

자세한 내용은 [Lambda Bridge README](lambda-bridge/README.md)를 참조하세요.

## Slack App 설정

1. [Slack API](https://api.slack.com/apps)에서 앱 생성
2. **OAuth & Permissions**에서 Bot Token Scopes 추가:
   - `channels:history`
   - `chat:write`
   - `groups:history`
   - `im:history`
3. **Event Subscriptions** 활성화:
   - Request URL: Lambda Receiver의 API Endpoint 입력
   - Subscribe to bot events:
     - `message.channels`
     - `message.groups`
     - `message.im`
4. 워크스페이스에 앱 설치 및 Bot Token 복사

## 테스트

### AgentCore Runtime 직접 테스트

```bash
agentcore invoke '{"prompt": "What is 10 times 5?"}' --agent hr_assistant_agent
```

### Slack에서 테스트

Slack에서 봇에게 메시지를 보내보세요:
- "What is 10 times 5?"
- "Calculate sqrt(144)"

## 모니터링

### CloudWatch Logs

```bash
# Lambda Receiver 로그
aws logs tail /aws/lambda/slack-bot-receiver --follow

# Lambda Bridge 로그
aws logs tail /aws/lambda/slack-bot-bridge --follow

# AgentCore Runtime 로그
aws logs tail /aws/bedrock-agentcore/hr_assistant_agent --follow --region us-east-1
```

### SQS Queue 모니터링

```bash
aws sqs get-queue-attributes \
    --queue-url <SQS_QUEUE_URL> \
    --attribute-names All
```

## 업데이트

각 서비스를 개별적으로 업데이트할 수 있습니다:

```bash
# AgentCore Runtime 업데이트
cd agentcore && bash deploy.sh

# Lambda Receiver 업데이트
cd lambda-receiver && bash deploy.sh

# Lambda Bridge 업데이트
cd lambda-bridge && bash deploy.sh
```

## 주요 특징

### AgentCore Direct Code Deploy

- Docker 설치 불필요
- CodeBuild가 클라우드에서 자동 빌드
- 빠른 배포 및 업데이트
- ARM64 아키텍처 자동 지원

### 비동기 처리

- SQS를 통한 안정적인 메시지 큐잉
- Lambda Bridge가 AgentCore 응답을 Slack으로 전송
- 긴 처리 시간에도 안정적인 동작

### 확장 가능한 구조

- 각 컴포넌트 독립적으로 배포 및 업데이트
- 여러 Slack 워크스페이스 지원 가능
- 다양한 Agent 도구 추가 가능

## 문제 해결

각 서비스의 README.md 파일을 참조하세요:
- [AgentCore README](agentcore/README.md)
- [Lambda Receiver README](lambda-receiver/README.md)
- [Lambda Bridge README](lambda-bridge/README.md)

## 라이선스

MIT License
