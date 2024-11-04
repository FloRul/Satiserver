# lambda/instance_control.py
from typing import Literal
from aws_lambda_powertools import Logger, Tracer
from aws_lambda_powertools.event_handler import (
    APIGatewayRestResolver,
    Response,
    content_types,
)
from aws_lambda_powertools.utilities.typing import LambdaContext
from aws_lambda_powertools.logging import correlation_paths
from aws_lambda_powertools.event_handler.openapi.exceptions import (
    RequestValidationError,
)
import boto3
import os
from botocore.exceptions import ClientError

# Initialize Powertools
logger = Logger()
tracer = Tracer()
app = APIGatewayRestResolver(enable_validation=True)

# Initialize AWS client
ec2 = boto3.client("ec2")


@app.exception_handler(RequestValidationError)
def handle_validation_error(ex: RequestValidationError):
    logger.error(
        "Request failed validation", path=app.current_event.path, errors=ex.errors()
    )

    return Response(
        status_code=422,
        content_type=content_types.APPLICATION_JSON,
        body="Invalid data",
    )


@app.post("/status")
@tracer.capture_method
def handle_instance_control():
    """Handle EC2 instance control requests"""
    try:
        instance_id = os.environ["INSTANCE_ID"]
        action = app.current_event.json_body["action"].lower()
        logger.info(f"Processing {action} request for instance {instance_id}")

        # Check current instance state
        response = ec2.describe_instances(InstanceIds=[instance_id])
        current_state = response["Reservations"][0]["Instances"][0]["State"]["Name"]

        # Prevent redundant actions
        if action == "start" and current_state == "running":
            logger.warning(f"Instance {instance_id} is already running")
            return {"statusCode": 400, "message": "Instance is already running"}

        if action == "stop" and current_state == "stopped":
            logger.warning(f"Instance {instance_id} is already stopped")
            return {"statusCode": 400, "message": "Instance is already stopped"}

        # Perform the requested action
        if action == "start":
            ec2.start_instances(InstanceIds=[instance_id])
            logger.info(f"Started instance {instance_id}")
        else:
            ec2.stop_instances(InstanceIds=[instance_id])
            logger.info(f"Stopped instance {instance_id}")

        return {
            "statusCode": 200,
            "message": f"Successfully {action}ed instance {instance_id}",
            "instanceId": instance_id,
            "action": action,
        }

    except ClientError as e:
        error_message = f"AWS Error: {str(e)}"
        logger.exception(error_message)
        return {"statusCode": 500, "message": error_message}


@app.get("/status")
@tracer.capture_method
def get_instance_status():
    """Get detailed EC2 instance status"""
    try:
        instance_id = os.environ["INSTANCE_ID"]
        logger.info(f"Retrieving status for instance {instance_id}")

        # Get instance details
        response = ec2.describe_instances(InstanceIds=[instance_id])
        instance = response["Reservations"][0]["Instances"][0]

        # Get status checks
        status_response = ec2.describe_instance_status(
            InstanceIds=[instance_id], IncludeAllInstances=True
        )
        status = (
            status_response["InstanceStatuses"][0]
            if status_response["InstanceStatuses"]
            else None
        )
        return {
            "statusCode": 200,
            "body": {
                "instanceId": instance_id,
                "state": instance["State"]["Name"],
                "publicIp": instance.get("PublicIpAddress", None),
                "launchTime": instance["LaunchTime"].isoformat(),
                "statusChecks": (
                    {
                        "systemStatus": (
                            status["SystemStatus"]["Status"]
                            if status
                            else "unavailable"
                        ),
                        "instanceStatus": (
                            status["InstanceStatus"]["Status"]
                            if status
                            else "unavailable"
                        ),
                    }
                    if status
                    else None
                ),
            },
        }

    except ClientError as e:
        error_message = f"AWS Error: {str(e)}"
        logger.exception(error_message)
        return {"statusCode": 500, "body": {"message": error_message}}


@logger.inject_lambda_context(correlation_id_path=correlation_paths.API_GATEWAY_REST)
@tracer.capture_lambda_handler
def handler(event: dict, context: LambdaContext) -> dict:
    """Main Lambda handler"""
    return app.resolve(event, context)
