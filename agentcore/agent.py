"""
AgentCore Worker - Strands Agent with HR Assistant Tools

AWS Bedrock AgentCore Runtime에서 실행되는 Strands Agent 애플리케이션입니다.
HR 문서 검색과 수학 계산 기능을 제공하는 AI 어시스턴트입니다.

Author: Jeonghun Sim
Created: 2025
Version: 1.0
"""

import logging
import math
import os
import sys
from typing import Dict, Any

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    stream=sys.stdout,
    force=True
)
logger = logging.getLogger(__name__)

# Import dependencies
try:
    import boto3
    from bedrock_agentcore import BedrockAgentCoreApp
    from strands import Agent, tool
    from strands.models import BedrockModel
    from strands_tools import calculator
except Exception as e:
    logger.error(f"Failed to import dependencies: {e}")
    raise

# Initialize BedrockAgentCoreApp
app = BedrockAgentCoreApp()

# Environment configuration
KNOWLEDGE_BASE_ID = os.environ.get('KNOWLEDGE_BASE_ID', 'LGZF8ULTDU')
KB_REGION = os.environ.get('KB_REGION', 'us-east-1')  # Knowledge Base는 서울
MODEL_ID = os.environ.get('MODEL_ID', 'openai.gpt-oss-120b-1:0')  # OpenAI GPT 모델
MODEL_REGION = os.environ.get('MODEL_REGION', 'us-east-1')  # 모델 리전
MAX_ITERATIONS = int(os.environ.get('MAX_ITERATIONS', '5'))  # 도구 사용 최대 횟수

# 스트리밍 미지원 모델 감지 (Llama 등)
STREAMING_UNSUPPORTED_MODELS = ['llama']
IS_LLAMA_MODEL = any(model_type in MODEL_ID.lower() for model_type in STREAMING_UNSUPPORTED_MODELS)
ENABLE_STREAMING = not IS_LLAMA_MODEL

logger.info(f"KB Fintech HR Assistant initialized - KB: {KNOWLEDGE_BASE_ID[:20] if KNOWLEDGE_BASE_ID else 'Not set'}..., Model: {MODEL_ID.split('/')[-1] if '/' in MODEL_ID else MODEL_ID}, Region: {MODEL_REGION}, Streaming: {ENABLE_STREAMING}")

# AWS client will be initialized lazily when needed
_bedrock_agent_runtime = None


def get_bedrock_client():
    """Lazy initialization of Bedrock Agent Runtime client"""
    global _bedrock_agent_runtime
    if _bedrock_agent_runtime is None:
        _bedrock_agent_runtime = boto3.client('bedrock-agent-runtime', region_name=KB_REGION)
    return _bedrock_agent_runtime

@tool
def search_hr_documents(query: str) -> str:
    """
    KB Fintech HR 문서를 검색합니다.
    
    Args:
        query: 검색할 질문이나 키워드
        
    Returns:
        검색 결과 텍스트
    """
    logger.info(f"[KB Search] {query[:50]}...")
    
    if not KNOWLEDGE_BASE_ID:
        return "Knowledge Base가 설정되지 않았습니다."
    
    try:
        client = get_bedrock_client()
        
        response = client.retrieve(
            knowledgeBaseId=KNOWLEDGE_BASE_ID,
            retrievalQuery={'text': query},
            retrievalConfiguration={
                'vectorSearchConfiguration': {
                    'numberOfResults': 5
                }
            }
        )
        
        results = []
        for item in response.get('retrievalResults', []):
            content = item.get('content', {}).get('text', '')
            score = item.get('score', 0)
            results.append(f"[관련도: {score:.2f}]\n{content}")
        
        if results:
            result_text = "\n\n---\n\n".join(results)
            logger.info(f"[KB Search] Found {len(results)} documents")
            return result_text
        else:
            return "관련 문서를 찾을 수 없습니다."
            
    except Exception as e:
        error_msg = f"검색 오류: {str(e)}"
        logger.error(f"[KB Search Error] {error_msg}")
        return error_msg

@tool
def calculator(expression: str) -> str:
    """
    수학 계산을 수행합니다. 급여, 연차, 수당 등을 계산할 때 사용합니다.
    
    Args:
        expression: 계산할 수식 (예: "10 * 5", "sqrt(16)", "2 + 3 * 4")
        
    Returns:
        계산 결과
    """
    logger.info(f"[Calculator] {expression}")
    
    try:
        # 안전한 수학 함수만 허용
        safe_dict = {
            'abs': abs, 'round': round, 'min': min, 'max': max,
            'sum': sum, 'pow': pow,
            'sqrt': math.sqrt, 'sin': math.sin, 'cos': math.cos,
            'tan': math.tan, 'log': math.log, 'exp': math.exp,
            'log10': math.log10, 'ceil': math.ceil, 'floor': math.floor,
            'pi': math.pi, 'e': math.e
        }
        
        result = eval(expression, {"__builtins__": {}}, safe_dict)
        logger.info(f"[Calculator] Result: {result}")
        return f"계산 결과: {result}"
        
    except Exception as e:
        error_msg = f"계산 오류: {str(e)}"
        logger.error(f"[Calculator Error] {error_msg}")
        return error_msg

# KB Fintech HR Assistant 페르소나
HR_SYSTEM_PROMPT = """당신은 KB Fintech 직원들을 위한 전문 'AI HR 어시스턴트'입니다.
당신의 목표는 직원들의 HR 관련 문의(규정, 복리후생, 휴가, 급여 등)에 대해 회사 내부 문서를 근거로 정확하고 친절하게 답변하는 것입니다.

## 업무 절차 (필수 준수)
1. **질문 분석 및 검색**: 사용자의 질문을 받으면 답변을 생성하기 전에 **반드시** `search_hr_documents` 도구를 사용하여 관련 문서를 검색하십시오. (사전 지식 사용 금지)
2. **정보 확인**: 검색된 문서 결과 내에서 사용자의 질문에 대한 정확한 답이 있는지 확인하십시오. 문서 기반으로 추론하여 답할 수 있습니다. 
3. **계산 수행 (필요 시)**: 급여, 휴가 일수, 수당 등의 계산이 필요한 경우, 문서에서 확인된 '공식'과 '기준'을 바탕으로 `calculator` 도구를 사용하여 정확한 값을 산출하십시오.
4. **답변 작성**: 확인된 정보와 계산 결과를 바탕으로 사용자에게 답변을 제공하십시오.

## 답변 원칙
- **증거 기반 (Evidence-Based)**: 오직 `search_hr_documents`를 통해 검색된 정보만을 사실로 간주하여 답변합니다. 문서에 없는 내용은 절대 추측하거나 지어내지 말고, "관련 문서를 찾을 수 없어 정확한 답변이 어렵습니다. 인사팀에 직접 문의 부탁드립니다."라고 정중히 안내하십시오.
- **친절한 어조**: 동료에게 말하듯 공손하고 친절한 경어체(한국어)를 사용하십시오.
- **명확성**: 법률적 용어나 복잡한 규정은 이해하기 쉬운 풀어서 설명하십시오.

## Slack 메시지 포맷팅 가이드 (엄격 준수)
Slack 가독성을 위해 아래 형식을 반드시 따르십시오:
- **코드 블록 금지**: 답변 전체나 일부를 마크다운 코드 블록(```)으로 감싸지 마십시오.
- **표(Table) 금지**: 복잡한 표 대신 리스트나 줄바꿈을 활용하십시오.
- **강조 표시**: 볼드 처리는 반드시 텍스트 앞뒤에 별표 하나만 사용하십시오. (예: *중요한 내용*)
- **목록**: 복잡한 서식 대신 하이픈(-)이나 숫자(1.)를 사용한 단순 텍스트 목록을 사용하십시오.

## 답변 예시
사용자: "제 연차 수당이 얼마인지 궁금해요. 기본급은 300만원입니다."

[내부 처리]
1. `search_hr_documents` 호출 -> "연차 수당 규정" 검색
2. 문서 확인: "통상임금의 100% 지급, 통상임금 = 기본급 / 209시간" 확인
3. `calculator` 호출 -> 3000000 / 209 계산

[최종 답변]
연차 수당에 대해 안내해 드립니다.

KB Fintech 규정에 따르면 연차 수당은 *통상임금의 100%*를 기준으로 산정됩니다.
기본급 300만 원을 기준으로 계산한 예상 수당은 다음과 같습니다.

- 1일 통상임금: 약 14,354원 (기본급 ÷ 209시간 × 8시간 기준)
- 잔여 연차 1일당 수당: *약 114,832원*

정확한 금액은 개인의 근태 상황에 따라 달라질 수 있으므로, 상세 내역은 급여 명세서를 참고 부탁드립니다.
"""

def get_agent() -> Agent:
    """
    매 요청마다 새로운 Agent 인스턴스를 생성합니다.
    대화 히스토리 충돌을 방지하기 위해 캐싱하지 않습니다.
    """
    try:
        bedrock_model = BedrockModel(
            model_id=MODEL_ID,
            region_name=MODEL_REGION,
            temperature=0.3,
            streaming=ENABLE_STREAMING
        )
        
        agent = Agent(
            model=bedrock_model,
            tools=[search_hr_documents, calculator],
            system_prompt=HR_SYSTEM_PROMPT,
            name="KB Fintech HR Assistant",
            description="KB Fintech 직원들의 HR 관련 질문에 답변하는 AI 어시스턴트",
            agent_id="kb-fintech-hr-assistant"
        )
        logger.info(f"KB Fintech HR Assistant Agent created (streaming={ENABLE_STREAMING})")
        return agent
    except Exception as e:
        logger.error(f"Failed to initialize agent: {e}", exc_info=True)
        raise


@app.entrypoint
def invoke(payload):
    """AgentCore Runtime 진입점 - 사용자 요청을 처리합니다."""
    try:
        user_message = payload.get("prompt", "Hello")
        verbose = payload.get("verbose", False)
        logger.info(f"[Request] {user_message[:100]}... (verbose={verbose})")
        
        agent = get_agent()
        
        # Agent 호출 (streaming은 BedrockModel에서 내부적으로 처리됨)
        result = agent(user_message)
        
        # 응답 추출
        if hasattr(result, 'message'):
            full_response = result.message
        else:
            full_response = str(result)
        
        logger.info(f"[Response] Completed ({len(full_response)} chars)")
        
        # 응답 구성
        response = {"result": full_response}
        
        return response
        
    except Exception as e:
        error_msg = f"Error: {str(e)}"
        logger.error(f"[Error] {error_msg}", exc_info=True)
        return {"result": error_msg}


if __name__ == "__main__":
    """AgentCore Runtime 애플리케이션 시작점"""
    logger.info("Starting KB Fintech HR Assistant...")
    app.run()