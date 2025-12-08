"""
Lambda Bridge - SQS와 AgentCore Runtime 연결
역할: SQS에서 메시지를 받아 AgentCore로 전달하고 Slack 응답
"""
import json
import logging
import os
import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# 환경 설정
AGENTCORE_RUNTIME_ARN = os.environ.get('AGENTCORE_RUNTIME_ARN')
SLACK_BOT_TOKEN = os.environ.get('SLACK_BOT_TOKEN')

# AWS 클라이언트 초기화
agentcore_client = boto3.client('bedrock-agentcore', region_name='us-east-1')
slack_client = None


def lambda_handler(event, context):
    """SQS에서 메시지를 받아 AgentCore로 처리"""
    logger.info(f"Processing {len(event['Records'])} messages")
    
    for record in event['Records']:
        try:
            body = json.loads(record['body'])
            
            if 'event' in body and body['event'].get('type') == 'message':
                handle_message(body['event'])
                    
        except Exception as e:
            logger.error(f"Error processing record: {str(e)}", exc_info=True)
            raise  # SQS DLQ로 전송


def handle_message(event_data):
    """Slack 메시지 처리 및 AgentCore로 전달"""
    # 봇 메시지 또는 빈 메시지 무시
    if event_data.get('bot_id') or not event_data.get('text', '').strip():
        return
    
    user = event_data.get('user')
    text = event_data.get('text')
    channel = event_data.get('channel')
    
    logger.info(f"Message from {user} in {channel}: {text}")
    
    try:
        # AgentCore Runtime 호출
        payload = json.dumps({"prompt": text}).encode()
        
        # 세션 ID 생성 (33자 이상 필요)
        import uuid
        session_id = f"slack-{channel}-{user}-{uuid.uuid4().hex}"
        
        response = agentcore_client.invoke_agent_runtime(
            agentRuntimeArn=AGENTCORE_RUNTIME_ARN,
            runtimeSessionId=session_id,
            payload=payload,
            qualifier="DEFAULT"
        )
        
        # 응답 파싱
        response_body = response['response'].read()
        response_data = json.loads(response_body)
        
        # Agent 응답 추출
        if 'result' in response_data:
            result = response_data['result']
            # result가 dict면 content 추출
            if isinstance(result, dict):
                if 'content' in result and isinstance(result['content'], list):
                    answer = result['content'][0].get('text', str(result))
                else:
                    answer = str(result)
            else:
                answer = str(result)
        elif 'output' in response_data:
            answer = response_data['output'].get('message', str(response_data['output']))
        else:
            answer = str(response_data)
        
        # Slack 메시지 전송
        send_slack_message(channel, answer)
        
        # 메트릭 로깅
        if 'metrics' in response_data:
            metrics = response_data['metrics']
            logger.info(f"Agent metrics: {metrics}")
        
    except Exception as e:
        logger.error(f"Error: {str(e)}", exc_info=True)
        error_msg = f"죄송합니다. 오류: {str(e)}"
        send_slack_message(channel, error_msg)


def send_slack_message(channel, text):
    """Slack 채널에 메시지 전송"""
    global slack_client
    
    # Lazy loading
    if slack_client is None:
        if not SLACK_BOT_TOKEN:
            logger.error("SLACK_BOT_TOKEN not set")
            return
        from slack_sdk import WebClient
        slack_client = WebClient(token=SLACK_BOT_TOKEN)
    
    response = slack_client.chat_postMessage(channel=channel, text=text)
    logger.info(f"Message sent to {channel}: {response['ts']}")
