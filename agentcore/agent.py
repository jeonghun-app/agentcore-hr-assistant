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

# Configure logging FIRST
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    stream=sys.stdout,
    force=True
)
logger = logging.getLogger(__name__)

logger.info("=" * 80)
logger.info("MODULE LOADING START")
logger.info(f"Python version: {sys.version}")
logger.info(f"Python executable: {sys.executable}")
logger.info(f"Current working directory: {os.getcwd()}")
logger.info(f"Module file: {__file__}")
logger.info("=" * 80)

try:
    logger.info("Importing boto3...")
    import boto3
    logger.info("✓ boto3 imported successfully")
except Exception as e:
    logger.error(f"✗ Failed to import boto3: {e}")
    raise

try:
    logger.info("Importing bedrock_agentcore...")
    from bedrock_agentcore import BedrockAgentCoreApp
    logger.info("✓ bedrock_agentcore imported successfully")
except Exception as e:
    logger.error(f"✗ Failed to import bedrock_agentcore: {e}")
    raise

try:
    logger.info("Importing strands...")
    from strands import Agent, tool
    from strands.models import BedrockModel
    logger.info("✓ strands imported successfully")
except Exception as e:
    logger.error(f"✗ Failed to import strands: {e}")
    raise

# Initialize BedrockAgentCoreApp
logger.info("Initializing BedrockAgentCoreApp...")
app = BedrockAgentCoreApp()
logger.info("✓ BedrockAgentCoreApp initialized")

# Environment configuration
logger.info("Reading environment variables...")
KNOWLEDGE_BASE_ID = os.environ.get('KNOWLEDGE_BASE_ID', '')
KB_REGION = os.environ.get('KB_REGION', 'us-east-1')
logger.info(f"KNOWLEDGE_BASE_ID: {KNOWLEDGE_BASE_ID if KNOWLEDGE_BASE_ID else '(not set)'}")
logger.info(f"KB_REGION: {KB_REGION}")

# AWS client will be initialized lazily when needed
_bedrock_agent_runtime = None


def get_bedrock_client():
    """Lazy initialization of Bedrock Agent Runtime client"""
    global _bedrock_agent_runtime
    if _bedrock_agent_runtime is None:
        logger.info(f"Creating Bedrock Agent Runtime client for region: {KB_REGION}")
        _bedrock_agent_runtime = boto3.client('bedrock-agent-runtime', region_name=KB_REGION)
        logger.info("✓ Bedrock Agent Runtime client created")
    return _bedrock_agent_runtime


logger.info("Defining tool: search_hr_documents")

@tool
def search_hr_documents(query: str) -> str:
    """
    HR 관련 문서를 검색합니다.
    
    Args:
        query: 검색할 질문이나 키워드
        
    Returns:
        검색 결과 텍스트
    """
    logger.info(f"[TOOL] search_hr_documents called with query: {query}")
    
    if not KNOWLEDGE_BASE_ID:
        return "Knowledge Base가 설정되지 않았습니다."
    
    try:
        # Get client lazily to ensure credentials are available
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
            logger.info(f"Found {len(results)} results")
            return result_text
        else:
            return "관련 문서를 찾을 수 없습니다."
            
    except Exception as e:
        error_msg = f"검색 오류: {str(e)}"
        logger.error(error_msg)
        return error_msg


logger.info("✓ search_hr_documents tool defined")
logger.info("Defining tool: my_calculator")

@tool
def my_calculator(expression: str) -> str:
    """
    수학 계산을 안전하게 수행합니다.
    
    Args:
        expression: 계산할 수식 (예: "10 * 5", "sqrt(16)")
        
    Returns:
        계산 결과
    """
    logger.info(f"[TOOL] my_calculator called with expression: {expression}")
    
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
        logger.info(f"Calculation successful: {expression} = {result}")
        return f"결과: {result}"
        
    except Exception as e:
        error_msg = f"계산 오류: {str(e)}"
        logger.error(f"Calculation error: {str(e)}")
        return error_msg


logger.info("✓ my_calculator tool defined")

# HR Assistant 페르소나
logger.info("Setting up HR Assistant persona...")
HR_SYSTEM_PROMPT = """당신은 친절하고 전문적인 HR 어시스턴트입니다.

주요 역할:
- 직원들의 HR 관련 질문에 답변합니다
- 회사 정책, 복리후생, 휴가 제도 등에 대한 정보를 제공합니다
- 필요시 HR 문서를 검색하여 정확한 정보를 제공합니다
- 간단한 계산이 필요한 경우 계산기 도구를 사용합니다

답변 스타일:
- 친절하고 공손한 어조를 유지합니다
- 명확하고 이해하기 쉽게 설명합니다
- 정확한 정보를 제공하기 위해 문서 검색을 적극 활용합니다
- 한국어로 답변합니다

사용 가능한 도구:
1. search_hr_documents: HR 관련 문서를 검색합니다
2. my_calculator: 수학 계산을 수행합니다
"""

# Agent will be initialized lazily on first request
_agent = None


def get_agent() -> Agent:
    """Lazy initialization of HR Assistant Agent"""
    global _agent
    if _agent is None:
        logger.info("=" * 80)
        logger.info("AGENT INITIALIZATION START")
        logger.info("=" * 80)
        
        try:
            logger.info("Creating BedrockModel...")
            bedrock_model = BedrockModel(
                model_id="anthropic.claude-sonnet-4-20250514-v1:0",
                region_name="us-east-1",
                temperature=0.3
            )
            logger.info("✓ BedrockModel created")
        except Exception as e:
            logger.error(f"✗ Failed to create BedrockModel: {e}", exc_info=True)
            raise
        
        try:
            logger.info("Creating Agent with tools...")
            logger.info(f"  - Tools: search_hr_documents, my_calculator")
            logger.info(f"  - System prompt length: {len(HR_SYSTEM_PROMPT)} chars")
            _agent = Agent(
                model=bedrock_model,
                tools=[search_hr_documents, my_calculator],
                system_prompt=HR_SYSTEM_PROMPT
            )
            logger.info("✓ Agent created successfully")
        except Exception as e:
            logger.error(f"✗ Failed to create Agent: {e}", exc_info=True)
            raise
        
        logger.info("=" * 80)
        logger.info("AGENT INITIALIZATION COMPLETE")
        logger.info("=" * 80)
    else:
        logger.info("Using cached Agent instance")
    
    return _agent


logger.info("=" * 80)
logger.info("MODULE LOADING COMPLETE - Ready to receive requests")
logger.info("=" * 80)


@app.entrypoint
def invoke(payload):
    """AgentCore Runtime 진입점 - 사용자 요청을 처리합니다."""
    logger.info("=" * 80)
    logger.info("INVOKE REQUEST RECEIVED")
    logger.info("=" * 80)
    
    try:
        user_message = payload.get("prompt", "Hello")
        logger.info(f"User message: {user_message}")
        logger.info(f"Payload keys: {list(payload.keys())}")
        
        # Get agent lazily - initialized on first request
        logger.info("Getting agent instance...")
        agent = get_agent()
        
        logger.info("Calling agent with user message...")
        result = agent(user_message)
        
        logger.info(f"Agent response received (length: {len(result.message)} chars)")
        logger.info("=" * 80)
        logger.info("INVOKE REQUEST COMPLETED SUCCESSFULLY")
        logger.info("=" * 80)
        
        return {"result": result.message}
        
    except Exception as e:
        error_msg = f"Error: {str(e)}"
        logger.error("=" * 80)
        logger.error("INVOKE REQUEST FAILED")
        logger.error(f"Error: {error_msg}")
        logger.error("=" * 80)
        logger.error("Full traceback:", exc_info=True)
        return {"result": error_msg}


if __name__ == "__main__":
    """AgentCore Runtime 애플리케이션 시작점"""
    logger.info("=" * 80)
    logger.info("STARTING AGENTCORE WORKER APPLICATION")
    logger.info("=" * 80)
    app.run()
