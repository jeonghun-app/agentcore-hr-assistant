# AgentCore 배포 가이드

## 현재 아키텍처
```
Slack → Lambda Receiver → SQS → Lambda Worker (문제 있음, 삭제 필요)
```

## 새로운 아키텍처
```
Slack → Lambda Receiver → SQS → Lambda Bridge → AgentCore Runtime
```

## 배포 순서

### 1단계: 기존 Worker 정리 (필수)
```bash
chmod +x cleanup_old_worker.sh
bash cleanup_old_worker.sh
```

**결과:**
- Lambda Worker 삭제
- SQS 트리거 제거
- (선택) Lambda Layer 삭제

---

### 2단계: AgentCore Runtime 배포 (필수)
```bash
chmod +x deploy_agentcore.sh
bash deploy_agentcore.sh
```

**중요:** 배포 완료 후 출력되는 **Agent ARN**을 복사해두세요!
```
예: arn:aws:bedrock-agentcore:us-east-1:081041735764:runtime/hr-assistant-agent-xxxxx
```

**결과:**
- Docker 이미지 빌드 및 ECR 푸시
- AgentCore Runtime 생성
- 테스트 실행

---

### 3단계: Lambda Bridge 배포 (필수)
```bash
chmod +x deploy_bridge.sh
bash deploy_bridge.sh
```

**프롬프트:** AgentCore Runtime ARN 입력 요청
- 2단계에서 복사한 ARN을 붙여넣기

**결과:**
- Lambda Bridge 생성
- SQS 트리거 연결
- 전체 파이프라인 완성

---

## 배포 후 테스트

### 1. Slack에서 테스트
```
Slack 채널에서 봇에게 메시지 전송:
"10 곱하기 5는?"
"연차는 몇일인가요?"
```

### 2. CloudWatch 로그 확인
```bash
# Bridge 로그
aws logs tail /aws/lambda/slack-bot-bridge --follow --region ap-northeast-2

# AgentCore 로그
aws logs tail /aws/bedrock-agentcore/hr-assistant-agent --follow --region us-east-1
```

### 3. 직접 AgentCore 호출 테스트
```bash
aws bedrock-agentcore invoke-agent-runtime \
  --agent-runtime-arn <YOUR_AGENT_ARN> \
  --runtime-session-id $(uuidgen) \
  --payload '{"prompt":"테스트 질문"}' \
  --region us-east-1 \
  response.json

cat response.json | jq .
```

---

## 트러블슈팅

### AgentCore 배포 실패
- Docker가 실행 중인지 확인
- AWS 자격증명 확인
- ECR 권한 확인

### Bridge 배포 실패
- AgentCore ARN이 올바른지 확인
- IAM 역할 권한 확인
- SQS Queue가 존재하는지 확인

### 메시지가 처리되지 않음
- SQS Queue에 메시지가 쌓이는지 확인
- Lambda Bridge 로그 확인
- AgentCore Runtime 상태 확인

---

## 리소스 정리 (필요시)

### AgentCore 삭제
```bash
aws bedrock-agentcore-control delete-agent-runtime \
  --agent-runtime-arn <YOUR_AGENT_ARN> \
  --region us-east-1
```

### Lambda Bridge 삭제
```bash
aws lambda delete-function \
  --function-name slack-bot-bridge \
  --region ap-northeast-2
```

### ECR 이미지 삭제
```bash
aws ecr delete-repository \
  --repository-name hr-assistant-agent \
  --force \
  --region us-east-1
```
