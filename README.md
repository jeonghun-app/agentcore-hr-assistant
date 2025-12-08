# Slack Bot with AgentCore Runtime

Strands Agent 기반 HR Assistant Bot - AgentCore Runtime 아키텍처

## 🏗️ 아키텍처

```
Slack → API Gateway → Lambda Receiver → SQS → Lambda Bridge → AgentCore Runtime (Strands Agent)
```

### 구성 요소

1. **Lambda Receiver**: Slack 이벤트를 받아 SQS로 전달
2. **SQS Queue**: 비동기 메시지 큐 (3초 타임아웃 방어)
3. **Lambda Bridge**: SQS에서 메시지를 읽어 AgentCore Runtime 호출
4. **AgentCore Runtime**: Strands Agent가 실행되는 관리형 컨테이너 환경

## 🚀 주요 기능

- **Strands Agent**: 자동 도구 선택 및 실행
- **Knowledge Base Tool**: HR 문서 검색 (IUK5AROV3D)
- **Calculator Tool**: 정확한 수학 계산
- **AgentCore Runtime**: AWS 관리형 인프라, 자동 스케일링, Observability

## 📦 빠른 시작

### 1. SQS 생성
```bash
python3 create_sqs_queue.py
```

### 2. Lambda Receiver 배포
```bash
bash create_lambda_receiver.sh
```

### 3. AgentCore Runtime 배포
```bash
bash deploy_agentcore.sh
```

이 스크립트는 다음을 자동으로 수행합니다:
- ✅ 의존성 확인/생성
- ✅ ECR 리포지토리 생성
- ✅ Docker 이미지 빌드 (ARM64)
- ✅ ECR 푸시
- ✅ AgentCore Runtime 생성 또는 업데이트
- ✅ 자동 테스트

### 4. Lambda Bridge 배포
```bash
bash deploy_bridge.sh
```

### 5. Slack 설정
1. https://api.slack.com/apps
2. Event Subscriptions → API Gateway 엔드포인트 입력
3. Bot Token Scopes: `channels:history`, `chat:write`, `groups:history`, `im:history`
4. Lambda Bridge 환경 변수에 `SLACK_BOT_TOKEN` 설정

## 📁 파일 구조

```
├── lambda_receiver.py          # Slack → SQS
├── lambda_bridge.py            # SQS → AgentCore Runtime → Slack
├── agentcore_worker_http.py    # Strands Agent (FastAPI)
├── Dockerfile.agentcore        # ARM64 컨테이너
├── python/                     # 의존성 (ARM64)
├── create_sqs_queue.py         # SQS 생성
├── create_lambda_receiver.sh   # Receiver 배포
├── deploy_agentcore.sh         # AgentCore 배포 (자동화)
├── deploy_bridge.sh            # Bridge 배포
├── create_agentcore.py         # AgentCore Runtime 생성 (단독)
├── test_agentcore.py           # Python 테스트
├── test_agentcore.sh           # Bash 테스트
├── iam_policy_receiver.json    # Receiver IAM 권한
├── iam_policy_bridge.json      # Bridge IAM 권한
├── requirements.txt            # Lambda 의존성
└── requirements_agentcore.txt  # AgentCore 의존성
```

## 🔧 환경 변수

### Lambda Receiver
- `SQS_QUEUE_URL`: SQS 대기열 URL

### Lambda Bridge
- `SLACK_BOT_TOKEN`: Slack Bot Token (xoxb-로 시작)
- `AGENTCORE_ARN`: AgentCore Runtime ARN

### AgentCore Worker
- `AWS_REGION`: ap-northeast-2 (Knowledge Base 리전)
- Knowledge Base ID: `IUK5AROV3D` (코드에 하드코딩)

## 🧪 테스트

### AgentCore Runtime 테스트
```bash
# Python 테스트 (여러 케이스)
python3 test_agentcore.py

# Bash 테스트 (빠른 확인)
bash test_agentcore.sh
```

### Slack에서 테스트
```
"What is 10 times 5?"
"Calculate 100 + 50"
"What is the square root of 144?"
```

### 로그 확인
```bash
# Lambda Receiver
aws logs tail /aws/lambda/slack-bot-receiver --follow --region ap-northeast-2

# Lambda Bridge
aws logs tail /aws/lambda/slack-bot-bridge --follow --region us-east-1

# AgentCore Runtime
aws logs tail /aws/bedrock-agentcore/hr-assistant-agent --follow --region us-east-1
```

## 🛠️ Strands Agent 도구

### 1. my_calculator
수학 계산 수행
- 기본 연산: +, -, *, /
- 함수: sqrt, sin, cos, tan, log, exp, pow
- 상수: pi, e

### 2. search_hr_knowledge_base
HR 문서 Knowledge Base에서 정보 검색
- Knowledge Base ID: IUK5AROV3D
- 모델: Claude 3.7 Sonnet (ap-northeast-2)
- 한국어 프롬프트 템플릿 포함

## 📊 배포된 리소스

### AWS 리소스
- **SQS**: `slack-bot-queue`
- **Lambda Receiver**: `slack-bot-receiver` (ap-northeast-2)
- **Lambda Bridge**: `slack-bot-bridge` (us-east-1)
- **AgentCore Runtime**: `hr_assistant_agent` (us-east-1)
- **ECR Repository**: `hr-assistant-agent` (us-east-1)
- **API Gateway**: `slack-bot-api` (ap-northeast-2)

### IAM Roles
- `slack-bot-receiver-role`: SQS 쓰기 권한
- `slack-bot-bridge-role`: SQS 읽기, AgentCore 호출 권한
- `slack-bot-worker-role`: Bedrock, Knowledge Base 접근 권한

##  업데이트 방법

### AgentCore Worker 코드 수정 후
```bash
# 자동 업데이트 (권장)
bash deploy_agentcore.sh

# 기존 Runtime이 있으면 자동으로 업데이트됩니다
```

### Lambda Bridge 수정 후
```bash
bash deploy_bridge.sh
```

## 🧹 리소스 정리

```bash
# Lambda 함수 삭제
aws lambda delete-function --function-name slack-bot-receiver --region ap-northeast-2
aws lambda delete-function --function-name slack-bot-bridge --region us-east-1

# SQS 삭제
aws sqs delete-queue --queue-url YOUR_QUEUE_URL --region ap-northeast-2

# AgentCore Runtime 삭제
aws bedrock-agentcore-control delete-agent-runtime \
  --agent-runtime-arn YOUR_AGENT_ARN \
  --region us-east-1

# ECR 이미지 삭제
aws ecr delete-repository --repository-name hr-assistant-agent --force --region us-east-1
```

## 📖 추가 문서

- [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md): 상세 배포 가이드
- [agentcore_arn.txt](agentcore_arn.txt): 배포된 AgentCore Runtime ARN

## 🎯 다음 단계

### Observability 설정 (선택사항)
1. CloudWatch Transaction Search 활성화
2. ADOT (OpenTelemetry) 추가
3. 메트릭 대시보드 생성

자세한 내용은 [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md)의 "Observability Enablement" 섹션 참조

## 💡 팁

- AgentCore Runtime은 자동으로 스케일링됩니다
- 기존 Runtime이 있으면 `deploy_agentcore.sh`가 자동으로 업데이트합니다
- ARN은 `agentcore_arn.txt`에 자동 저장됩니다
- 테스트 시 영어 질문 사용 (AWS CLI ASCII 제한)
- 한국어는 Slack을 통해 테스트하세요
