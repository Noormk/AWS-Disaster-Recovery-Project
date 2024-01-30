import boto3

def lambda_handler(event, context):
    autoscaling_client = boto3.client('autoscaling')
    autoscaling_client.update_auto_scaling_group(
        AutoScalingGroupName='your-auto-scaling-group',
        MinSize=new_min_size,
        MaxSize=new_max_size
    )

    return {
        'statusCode': 200,
        'body': 'Resources scaled successfully.'
    }
