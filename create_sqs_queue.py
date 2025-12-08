"""
SQS 표준 대기열 생성 스크립트
"""
import boto3
import os

REGION = os.getenv('AWS_REGION', 'ap-northeast-2')
QUEUE_NAME = os.getenv('SQS_QUEUE_NAME', 'slack-bot-queue')


def create_sqs_queue():
    """AWS SQS 표준 대기열 생성"""
    sqs = boto3.client('sqs', region_name=REGION)
    
    try:
        response = sqs.create_queue(
            QueueName=QUEUE_NAME,
            Attributes={
                'DelaySeconds': '0',
                'MessageRetentionPeriod': '345600',  # 4일
                'VisibilityTimeout': '300',  # 5분
                'ReceiveMessageWaitTimeSeconds': '0'
            }
        )
        queue_url = response['QueueUrl']
        print(f"✅ SQS 대기열 생성 완료!")
        
    except sqs.exceptions.QueueNameExists:
        print(f"⚠️  대기열이 이미 존재합니다.")
        queue_url = sqs.get_queue_url(QueueName=QUEUE_NAME)['QueueUrl']
    
    # Queue 정보 가져오기
    attrs = sqs.get_queue_attributes(
        QueueUrl=queue_url,
        AttributeNames=['QueueArn']
    )
    
    result = {
        'queue_name': QUEUE_NAME,
        'queue_url': queue_url,
        'queue_arn': attrs['Attributes']['QueueArn']
    }
    
    print(f"Queue Name: {result['queue_name']}")
    print(f"Queue URL: {result['queue_url']}")
    print(f"Queue ARN: {result['queue_arn']}")
    print(f"\n📋 환경 변수: SQS_QUEUE_URL={result['queue_url']}")
    
    return result


if __name__ == '__main__':
    create_sqs_queue()
