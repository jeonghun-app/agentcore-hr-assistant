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
except Exception as e:
    logger.error(f"Failed to import dependencies: {e}")
    raise

# Initialize BedrockAgentCoreApp
app = BedrockAgentCoreApp()

# Environment configuration
KNOWLEDGE_BASE_ID = os.environ.get('KNOWLEDGE_BASE_ID', '')
KB_REGION = os.environ.get('KB_REGION', 'us-east-1')
MODEL_ID = os.environ.get('MODEL_ID', 'us.anthropic.claude-sonnet-4-20250514-v1:0')

logger.info(f"KB Fintech HR Assistant initialized - KB: {KNOWLEDGE_BASE_ID[:20] if KNOWLEDGE_BASE_ID else 'Not set'}..., Model: {MODEL_ID.split('/')[-1] if '/' in MODEL_ID else MODEL_ID}")

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
def my_calculator(expression: str) -> str:
    """
    HR 문서의 규정에 따른 수학 계산을 수행합니다.
    
    Args:
        expression: 계산할 수식 (예: "10 * 5", "sqrt(16)")
        
    Returns:
        계산 결과
    """
    logger.info(f"[Calculator] {expression}")
    
    try:
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
        return f"결과: {result}"
        
    except Exception as e:
        error_msg = f"계산 오류: {str(e)}"
        logger.error(f"[Calculator Error] {error_msg}")
        return error_msg

# KB Fintech HR Assistant 페르소나
HR_SYSTEM_PROMPT = """당신은 KB Fintech의 친절하고 전문적인 HR 어시스턴트입니다.

주요 역할:
- KB Fintech 직원들의 HR 관련 질문에 답변합니다
- 회사 정책, 복리후생, 휴가 제도, 급여, 인사 규정 등에 대한 정보를 제공합니다
- 반드시 HR 문서를 검색하여 문서에 기반한 정확한 정보만 제공합니다
- HR 문서의 내용을 참고하여 필요한 계산을 수행합니다

답변 원칙:
- 모든 답변은 반드시 HR 문서 검색 결과에 기반해야 합니다
- 문서에서 찾을 수 없는 정보는 추측하지 않고, 인사팀에 문의하도록 안내합니다
- 급여, 수당, 휴가 일수 등 계산이 필요한 경우 HR 문서의 규정을 확인한 후 계산기를 사용합니다
- 친절하고 공손한 어조를 유지하며, 명확하고 이해하기 쉽게 설명합니다
- 한국어로 답변합니다

사용 가능한 도구:
1. search_hr_documents: KB Fintech HR 문서를 검색합니다 (모든 답변 전에 반드시 사용)
2. my_calculator: HR 문서의 규정에 따른 수학 계산을 수행합니다
"""

# Agent will be initialized lazily on first request
_agent = None


def get_agent() -> Agent:
    """Lazy initialization of KB Fintech HR Assistant Agent"""
    global _agent
    if _agent is None:
        try:
            bedrock_model = BedrockModel(
                model_id=MODEL_ID,
                region_name="us-east-1",
                temperature=0.3
            )
            
            _agent = Agent(
                model=bedrock_model,
                tools=[search_hr_documents, my_calculator],
                system_prompt=HR_SYSTEM_PROMPT
            )
            logger.info("KB Fintech HR Assistant Agent initialized successfully")
        except Exception as e:
            logger.error(f"Failed to initialize agent: {e}", exc_info=True)
            raise
    
    return _agent


@app.entrypoint
def invoke(payload):
    """AgentCore Runtime 진입점 - 사용자 요청을 처리합니다."""
    try:
        user_message = payload.get("prompt", "Hello")
        logger.info(f"[Request] {user_message[:100]}...")
        
        agent = get_agent()
        result = agent(user_message)
        
        logger.info(f"[Response] Completed ({len(result.message)} chars)")
        return {"result": result.message}
        
    except Exception as e:
        error_msg = f"Error: {str(e)}"
        logger.error(f"[Error] {error_msg}", exc_info=True)
        return {"result": error_msg}


if __name__ == "__main__":
    """AgentCore Runtime 애플리케이션 시작점"""
    logger.info("Starting KB Fintech HR Assistant...")
    app.run()
