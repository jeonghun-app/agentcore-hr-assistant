"""
AgentCore Worker - Strands Agent with BedrockAgentCoreApp
"""
import logging
import boto3
from bedrock_agentcore import BedrockAgentCoreApp
from strands import Agent, tool

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# BedrockAgentCoreApp 초기화
app = BedrockAgentCoreApp()

# 환경 설정
KNOWLEDGE_BASE_ID = ''  # Knowledge Base ID를 여기에 입력하세요
bedrock_runtime = boto3.client('bedrock-agent-runtime', region_name='ap-northeast-2')


@tool
def my_calculator(expression: str) -> str:
    """수학 계산을 수행합니다."""
    logger.info(f"Calculating: {expression}")
    try:
        import math
        safe_dict = {
            'abs': abs, 'round': round, 'min': min, 'max': max,
            'sum': sum, 'pow': pow,
            'sqrt': math.sqrt, 'sin': math.sin, 'cos': math.cos,
            'tan': math.tan, 'log': math.log, 'exp': math.exp,
            'pi': math.pi, 'e': math.e
        }
        result = eval(expression, {"__builtins__": {}}, safe_dict)
        return f"결과: {result}"
    except Exception as e:
        return f"계산 오류: {str(e)}"


@tool
def search_hr_knowledge_base(query: str) -> str:
    """HR 문서 Knowledge Base에서 정보를 검색합니다."""
    logger.info(f"Searching Knowledge Base: {query}")
    try:
        response = bedrock_runtime.retrieve_and_generate(
            input={'text': query},
            retrieveAndGenerateConfiguration={
                'type': 'KNOWLEDGE_BASE',
                'knowledgeBaseConfiguration': {
                    'knowledgeBaseId': KNOWLEDGE_BASE_ID,
                    'modelArn': '',  # Knowledge Base 모델 ARN을 여기에 입력하세요
                }
            }
        )
        return response.get('output', {}).get('text', '답변을 생성할 수 없습니다.')
    except Exception as e:
        logger.error(f"Knowledge Base search error: {str(e)}")
        return f"검색 중 오류가 발생했습니다: {str(e)}"


logger.info("Initializing Strands Agent...")

@app.entrypoint
def invoke(payload):
    """AgentCore entrypoint"""
    try:
        user_message = payload.get("prompt", "Hello! How can I help you today?")
        logger.info(f"Processing: {user_message}")
        
        # Lazy init agent
        hr_agent = Agent(
            model="",  # AgentCore 모델 ARN을 여기에 입력하세요
            tools=[search_hr_knowledge_base, my_calculator],
            system_prompt="당신은 친절하고 전문적인 HR Assistant입니다."
        )
        
        result = hr_agent(user_message)
        return {"result": result.message}
    except Exception as e:
        logger.error(f"Error in invoke: {str(e)}", exc_info=True)
        return {"result": f"Error: {str(e)}"}


if __name__ == "__main__":
    app.run()
