#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Slack Bot Lambda Receiver

Slack 이벤트를 수신하여 SQS 대기열로 전달하는 AWS Lambda 함수입니다.
Slack의 3초 타임아웃 제한을 회피하기 위해 즉시 응답을 반환하고,
실제 메시지 처리는 SQS를 통해 비동기로 수행합니다.

Architecture:
    Slack → API Gateway → Lambda Receiver → SQS → Lambda Bridge

Author: Jeonghun Sim
Created: 2025
Version: 1.0
"""

import json
import logging
import os
from typing import Dict, Any

import boto3

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
sqs_client = boto3.client('sqs', region_name=os.environ.get('AWS_REGION', 'ap-northeast-2'))
SQS_QUEUE_URL = os.environ.get('SQS_QUEUE_URL')


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """AWS Lambda 진입점 - Slack 이벤트를 처리합니다.
    
    Slack에서 전송된 이벤트를 수신하여 적절히 처리하고,
    메시지 이벤트의 경우 SQS 대기열로 전달합니다.
    
    Args:
        event: API Gateway에서 전달된 이벤트 데이터
            - body: Slack에서 전송한 JSON 페이로드
            - headers: HTTP 헤더 정보
        context: Lambda 실행 컨텍스트 (사용하지 않음)
    
    Returns:
        HTTP 응답 딕셔너리:
            - statusCode: HTTP 상태 코드 (200 또는 500)
            - body: JSON 형태의 응답 본문
    
    Raises:
        Exception: SQS 전송 실패 시 500 에러 반환
    """
    try:
        logger.info(f"Received event: {json.dumps(event)}")
        
        # API Gateway 이벤트 검증
        if 'body' not in event:
            return _create_response(200, {'message': 'OK'})
        
        # JSON 파싱
        body = json.loads(event['body']) if isinstance(event['body'], str) else event['body']
        
        # 1. Slack URL Verification 처리 (앱 설정 시 최초 1회)
        if body.get('type') == 'url_verification':
            logger.info("Processing URL verification challenge")
            return _create_response(200, {'challenge': body['challenge']})
        
        # 2. Event Callback 처리 (실제 메시지 이벤트)
        if body.get('type') == 'event_callback':
            event_data = body.get('event', {})
            
            # 봇 자신의 메시지 무시 (무한 루프 방지)
            if event_data.get('bot_id'):
                logger.info("Ignoring bot message to prevent recursion")
                return _create_response(200, {'ok': True})
            
            # SQS로 메시지 전송 (비동기 처리)
            if SQS_QUEUE_URL:
                send_to_sqs(body)
                logger.info("Message forwarded to SQS for processing")
            else:
                logger.error("SQS_QUEUE_URL environment variable not configured")
            
            # Slack에 즉시 200 응답 (3초 타임아웃 방어)
            return _create_response(200, {'ok': True})
        
        # 기타 이벤트 타입 처리
        return _create_response(200, {'message': 'OK'})
        
    except Exception as e:
        logger.error(f"Error processing Slack event: {str(e)}", exc_info=True)
        return _create_response(500, {'error': str(e)})


def send_to_sqs(message_body: Dict[str, Any]) -> None:
    """SQS 대기열로 메시지를 전송합니다.
    
    Slack 이벤트 데이터를 JSON 문자열로 직렬화하여
    SQS 대기열에 전송합니다. Lambda Bridge에서 처리됩니다.
    
    Args:
        message_body: Slack에서 받은 이벤트 데이터 딕셔너리
    
    Raises:
        Exception: SQS 전송 실패 시 예외 발생
    """
    try:
        response = sqs_client.send_message(
            QueueUrl=SQS_QUEUE_URL,
            MessageBody=json.dumps(message_body, ensure_ascii=False)
        )
        logger.info(f"Message successfully sent to SQS: {response['MessageId']}")
    except Exception as e:
        logger.error(f"Failed to send message to SQS: {str(e)}", exc_info=True)
        raise


def _create_response(status_code: int, body: Dict[str, Any]) -> Dict[str, Any]:
    """HTTP 응답 객체를 생성합니다.
    
    Args:
        status_code: HTTP 상태 코드
        body: 응답 본문 딕셔너리
    
    Returns:
        API Gateway 형식의 응답 딕셔너리
    """
    return {
        'statusCode': status_code,
        'body': json.dumps(body, ensure_ascii=False),
        'headers': {
            'Content-Type': 'application/json; charset=utf-8'
        }
    }
