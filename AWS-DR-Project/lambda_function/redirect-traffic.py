import boto3

def lambda_handler(event, context):
    return {
        'statusCode': 200,
        'body': 'Traffic redirected successfully.'
    }
