# AgentCore Runtime 배포

AWS Bedrock AgentCore Runtime에 Strands Agent를 직접 코드 배포(Direct Code Deploy) 방식으로 배포합니다.

## 사전 준비

1. AWS CLI 설치 및 설정
2. Python 3.10 이상
3. AgentCore CLI 설치:
   ```bash
   pip install bedrock-agentcore-starter-toolkit
   ```

## 배포 방법

### 1. 배포 스크립트 실행

```bash
cd agentcore
bash deploy.sh
```

스크립트 실행 시 다음 정보를 입력합니다:
- **Agent Name**: AgentCore Runtime 이름 (기본값: hr_assistant_agent)
  - 주의: 하이픈(-) 사용 불가, 언더스코어(_)만 가능
- **AWS Region**: 배포할 리전 (기본값: us-east-1)
- **Python Runtime**: Python 버전 (기본값: PYTHON_3_13)
- **Knowledge Base ID**: (선택사항) Bedrock Knowledge Base ID
- **KB Region**: Knowledge Base 리전 (기본값: us-east-1)

### 2. 배포 과정

스크립트는 다음 작업을 자동으로 수행합니다:

1. AgentCore CLI 설치 확인
2. Agent 설정 (`agentcore configure`)
   - Direct Code Deploy 방식 사용
   - HTTP 프로토콜 설정
   - 자동으로 실행 역할 생성
3. Agent 배포 (`agentcore launch`)
   - CodeBuild에서 자동으로 컨테이너 빌드
   - ARM64 아키텍처로 자동 빌드
   - S3에 소스 코드 업로드
4. 배포 상태 확인

### 3. 배포 확인

```bash
# Agent 상태 확인
agentcore status --agent hr_assistant_agent --verbose

# Agent ARN 확인
agentcore status --agent hr_assistant_agent --verbose | grep agent_arn

# 로그 확인
aws logs tail /aws/bedrock-agentcore/hr_assistant_agent --follow --region us-east-1
```

## 테스트

### AgentCore CLI로 테스트

```bash
# 계산 테스트
agentcore invoke '{"prompt": "What is 10 times 5?"}' --agent hr_assistant_agent

# 수학 함수 테스트
agentcore invoke '{"prompt": "Calculate sqrt(144)"}' --agent hr_assistant_agent
```

### Lambda Bridge를 통한 테스트

Slack에서 봇에게 메시지를 보내면 Lambda Bridge가 AgentCore Runtime을 호출합니다.

## 업데이트

코드를 수정한 후:

```bash
cd agentcore
bash deploy.sh
```

기존 Agent가 자동으로 업데이트됩니다.

## 주요 명령어

```bash
# Agent 목록 확인
agentcore configure list

# 기본 Agent 설정
agentcore configure set-default hr_assistant_agent

# 세션 중지
agentcore stop-session --agent hr_assistant_agent

# Agent 삭제
agentcore destroy --agent hr_assistant_agent
```

## Direct Code Deploy 장점

- **Docker 불필요**: 로컬에 Docker 설치 없이 배포 가능
- **자동 빌드**: CodeBuild가 클라우드에서 자동으로 컨테이너 빌드
- **빠른 배포**: 코드만 업로드하면 자동으로 배포
- **ARM64 지원**: 자동으로 ARM64 아키텍처로 빌드

## 문제 해결

### AgentCore CLI 설치 실패

```bash
pip install --upgrade bedrock-agentcore-starter-toolkit
```

### 배포 실패

```bash
# 상세 로그 확인
agentcore status --agent hr_assistant_agent --verbose

# AWS 인증 확인
aws sts get-caller-identity
```

### 모델 접근 권한 오류

AWS Console → Bedrock → Model access에서 Claude Sonnet 4 모델 활성화

## 환경 변수

AgentCore Runtime에서 사용 가능한 환경 변수:

- `KNOWLEDGE_BASE_ID`: Bedrock Knowledge Base ID (선택사항)
- `KB_REGION`: Knowledge Base 리전 (기본값: us-east-1)
- `KB_MODEL_ARN`: Knowledge Base 검색 모델 ARN (자동 설정)
- `AGENTCORE_MODEL_ARN`: Agent 모델 ARN (자동 설정)

### 배포 시 환경 변수 설정

`deploy.sh` 스크립트가 자동으로 환경 변수를 설정합니다:
- Knowledge Base ID를 입력하면 자동으로 전달
- 모델 ARN은 Claude Sonnet 4로 자동 설정

### 수동으로 환경 변수 설정

배포 후 환경 변수를 변경하려면:

```bash
# Agent 재배포 (환경 변수 포함)
agentcore launch --agent hr_assistant_agent \
    --env KNOWLEDGE_BASE_ID=your-kb-id \
    --env KB_REGION=us-east-1 \
    --auto-update-on-conflict
```

또는 `.bedrock_agentcore.yaml` 파일을 직접 수정한 후 재배포할 수 있습니다.

## 아키텍처

```
Slack → Lambda Receiver → SQS → Lambda Bridge → AgentCore Runtime (Direct Code Deploy)
                                                      ↓
                                              Strands Agent + Tools
```

## 파일 구조

```
agentcore/
├── agentcore_worker_http.py  # Agent 애플리케이션 코드
├── requirements.txt          # Python 의존성
├── deploy.sh                 # 배포 스크립트
└── README.md                 # 이 파일
```
