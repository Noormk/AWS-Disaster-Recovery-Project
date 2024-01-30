import boto3

def lambda_handler(event, context):

    source_region = event['sourceRegion']
    destination_region = event['destinationRegion']
    source_db_identifier = event['sourceDBIdentifier']
    destination_db_identifier = event['destinationDBIdentifier']

    source_rds_client = boto3.client('rds', region_name=source_region)
    destination_rds_client = boto3.client('rds', region_name=destination_region)

    try:
        latest_snapshot = source_rds_client.describe_db_snapshots(
            DBInstanceIdentifier=source_db_identifier,
            SnapshotType='automated'
        )['DBSnapshots'][0]['DBSnapshotIdentifier']

        destination_rds_client.copy_db_snapshot(
            SourceDBSnapshotIdentifier=f"{source_db_identifier}-{latest_snapshot}",
            TargetDBSnapshotIdentifier=f"{destination_db_identifier}-{latest_snapshot}",
            SourceRegion=source_region
        )

        destination_rds_client.restore_db_instance_from_db_snapshot(
            DBInstanceIdentifier=destination_db_identifier,
            DBSnapshotIdentifier=f"{destination_db_identifier}-{latest_snapshot}",
            AutoMinorVersionUpgrade=True,
            PubliclyAccessible=False
        )

        return {
            'statusCode': 200,
            'body': 'Data replication and consistency maintained successfully.'
        }

    except Exception as e:
        return {
            'statusCode': 500,
            'body': f'Error: {str(e)}'
        }
    