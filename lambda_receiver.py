"""
Lambda Receiver - Slack 이벤트를 받아 SQS로 전달
역할: 3초 타임아웃 방어를 위해 즉시 응답 후 SQS로 메시지 전달
"""
import json
import logging
import boto3
import os

logger = logging.getLogger()
logger.setLevel(logging.INFO)

sqs_client = boto3.client('sqs', region_name='ap-northeast-2')
SQS_QUEUE_URL = os.environ.get('SQS_QUEUE_URL')


def lambda_handler(event, context):
    """Slack 메시지를 받아 SQS로 전달"""
    try:
        logger.info(f"Received event: {json.dumps(event)}")
        
        if 'body' not in event:
            return {'statusCode': 200, 'body': json.dumps({'message': 'OK'})}
        
        body = json.loads(event['body']) if isinstance(event['body'], str) else event['body']
        
        # 1. Slack URL Verification (최초 1회)
        if body.get('type') == 'url_verification':
            return {
                'statusCode': 200,
                'body': json.dumps({'challenge': body['challenge']})
            }
        
        # 2. Event Callback 처리
        if body.get('type') == 'event_callback':
            event_data = body.get('event', {})
            
            # 봇 자신의 메시지 무시 (재귀 방지)
            if event_data.get('bot_id'):
                logger.info("Ignoring bot message")
                return {'statusCode': 200, 'body': json.dumps({'ok': True})}
            
            # SQS로 메시지 전송
            if SQS_QUEUE_URL:
                send_to_sqs(body)
            else:
                logger.error("SQS_QUEUE_URL not configured")
            
            # Slack에 즉시 200 응답 (3초 타임아웃 방어)
            return {'statusCode': 200, 'body': json.dumps({'ok': True})}
        
        return {'statusCode': 200, 'body': json.dumps({'message': 'OK'})}
        
    except Exception as e:
        logger.error(f"Error: {str(e)}", exc_info=True)
        return {'statusCode': 500, 'body': json.dumps({'error': str(e)})}


def send_to_sqs(message_body):
    """SQS 대기열로 메시지 전송"""
    try:
        response = sqs_client.send_message(
            QueueUrl=SQS_QUEUE_URL,
            MessageBody=json.dumps(message_body)
        )
        logger.info(f"Message sent to SQS: {response['MessageId']}")
    except Exception as e:
        logger.error(f"Error sending to SQS: {str(e)}", exc_info=True)
        raise
