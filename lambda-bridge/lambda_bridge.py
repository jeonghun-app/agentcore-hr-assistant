#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Slack Bot Lambda Bridge

SQS 대기열에서 메시지를 수신하여 AWS Bedrock AgentCore Runtime으로 전달하고,
처리 결과를 Slack 채널로 전송하는 AWS Lambda 함수입니다.

Architecture:
    SQS → Lambda Bridge → AgentCore Runtime → Slack Response

Author: Jeonghun Sim
Created: 2025
Version: 1.0
"""

import json
import logging
import os
import uuid
from typing import Dict, List, Any, Optional

import boto3

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Environment configuration
AGENTCORE_RUNTIME_ARN = os.environ.get('AGENTCORE_RUNTIME_ARN')
SLACK_BOT_TOKEN = os.environ.get('SLACK_BOT_TOKEN')
AGENTCORE_REGION = os.environ.get('AGENTCORE_REGION', 'us-east-1')

# AWS clients initialization
agentcore_client = boto3.client('bedrock-agentcore', region_name=AGENTCORE_REGION)
slack_client: Optional[Any] = None  # Lazy initialization


def lambda_handler(event: Dict[str, Any], context: Any) -> None:
    """AWS Lambda 진입점 - SQS 메시지를 처리합니다."""
    records = event.get('Records', [])
    logger.info(f"Processing {len(records)} SQS messages")
    
    for record in records:
        try:
            body = json.loads(record['body'])
            
            if 'event' in body and body['event'].get('type') == 'message':
                handle_message(body['event'])
            else:
                logger.debug(f"Skipping non-message event: {body.get('type')}")
                    
        except Exception as e:
            logger.error(f"Error processing SQS record: {str(e)}", exc_info=True)
            raise


def handle_message(event_data: Dict[str, Any]) -> None:
    """Slack 메시지를 처리하고 AgentCore Runtime으로 전달합니다."""
    if event_data.get('bot_id') or not event_data.get('text', '').strip():
        logger.debug("Skipping bot message or empty message")
        return
    
    user = event_data.get('user')
    text = event_data.get('text')
    channel = event_data.get('channel')
    
    logger.info(f"Processing message from user {user} in channel {channel}: {text[:100]}...")
    
    try:
        payload = json.dumps({"prompt": text}, ensure_ascii=False).encode('utf-8')
        session_id = f"slack-{channel}-{user}-{uuid.uuid4().hex}"
        
        logger.info(f"Invoking AgentCore with session ID: {session_id}")
        
        # AgentCore Runtime 호출
        logger.info(f"Calling AgentCore Runtime ARN: {AGENTCORE_RUNTIME_ARN}")
        
        response = agentcore_client.invoke_agent_runtime(
            agentRuntimeArn=AGENTCORE_RUNTIME_ARN,
            runtimeSessionId=session_id,
            payload=payload
        )
        
        # 응답 읽기
        response_body = response.get('response')
        if hasattr(response_body, 'read'):
            response_body = response_body.read()
        
        if isinstance(response_body, bytes):
            response_body = response_body.decode('utf-8')
        
        response_data = json.loads(response_body)
        logger.info(f"AgentCore response: {json.dumps(response_data)[:200]}...")
        
        answer = _extract_agent_response(response_data)
        send_slack_message(channel, answer)
        _log_metrics(response_data)
        
    except Exception as e:
        logger.error(f"Error processing message: {str(e)}", exc_info=True)
        error_msg = f"죄송합니다. 오류가 발생했습니다: {str(e)}"
        send_slack_message(channel, error_msg)


def send_slack_message(channel: str, text: str) -> None:
    """Slack 채널에 메시지를 전송합니다."""
    global slack_client
    
    if slack_client is None:
        if not SLACK_BOT_TOKEN:
            logger.error("SLACK_BOT_TOKEN environment variable not configured")
            return
        
        try:
            from slack_sdk import WebClient
            slack_client = WebClient(token=SLACK_BOT_TOKEN)
            logger.info("Slack client initialized successfully")
        except ImportError:
            logger.error("slack_sdk package not available")
            return
    
    try:
        response = slack_client.chat_postMessage(
            channel=channel, 
            text=text,
            unfurl_links=False,
            unfurl_media=False
        )
        logger.info(f"Message sent to channel {channel}: timestamp {response['ts']}")
    except Exception as e:
        logger.error(f"Failed to send Slack message: {str(e)}", exc_info=True)
        raise


def _extract_agent_response(response_data: Dict[str, Any]) -> str:
    """AgentCore 응답에서 메시지를 추출합니다."""
    # 다양한 응답 형식 처리
    if 'result' in response_data:
        result = response_data['result']
        if isinstance(result, dict):
            # Strands Agent 응답 형식
            if 'message' in result:
                return result['message']
            elif 'content' in result and isinstance(result['content'], list):
                return result['content'][0].get('text', str(result))
            else:
                return str(result)
        else:
            return str(result)
    elif 'output' in response_data:
        output = response_data['output']
        if isinstance(output, dict):
            return output.get('message', str(output))
        else:
            return str(output)
    elif 'message' in response_data:
        return response_data['message']
    else:
        logger.warning(f"Unknown response format: {response_data}")
        return str(response_data)


def _log_metrics(response_data: Dict[str, Any]) -> None:
    """AgentCore 응답에서 메트릭을 추출하여 로깅합니다."""
    if 'metrics' in response_data:
        metrics = response_data['metrics']
        logger.info(f"AgentCore performance metrics: {json.dumps(metrics, indent=2)}")
