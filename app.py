#!/usr/bin/env python3

from aws_cdk import core as cdk

from stacks.back_end.s3_stack.s3_stack import S3Stack
from stacks.back_end.vpc_stack import VpcStack
from stacks.back_end.s3_consumer_on_ec2_stack.s3_consumer_on_ec2_stack import S3ConsumerOnEC2Stack
from stacks.back_end.serverless_s3_producer_stack.serverless_s3_producer_stack import ServerlessS3ProducerStack

from stacks.back_end.s3_stack.s3_access_points_stack import S3AccessPointsStack


app = cdk.App()

# S3 Bucket to hold our store events
sales_events_bkt_stack = S3Stack(
    app,
    # f"{app.node.try_get_context('project')}-sales-events-bkt-stack",
    f"sales-events-bkt-stack",
    stack_log_level="INFO",
    description="Miztiik Automation: S3 Bucket to hold our store events"
)

# VPC Stack for hosting Secure workloads & Other resources
vpc_stack = VpcStack(
    app,
    f"{app.node.try_get_context('project')}-vpc-stack",
    stack_log_level="INFO",
    description="Miztiik Automation: Custom Multi-AZ VPC"
)

# App Server to consume S3 Access Points
sales_event_consumer_on_ec2 = S3ConsumerOnEC2Stack(
    app,
    f"sales-event-consumer-on-ec2-stack",
    vpc=vpc_stack.vpc,
    ec2_instance_type="t2.medium",
    stack_log_level="INFO",
    description="Miztiik Automation: App Server to consume 'Sales Event' - S3 Access Points"
)


# Produce store events using AWS Lambda and store them in S3
serverless_s3_producer_stack = ServerlessS3ProducerStack(
    app,
    f"inventory-event-consumer-on-lambda-stack",
    stack_log_level="INFO",
    sales_event_bkt=sales_events_bkt_stack.data_bkt,
    lambda_consumer_ap="lambda-consumer",
    description="Miztiik Automation: Produce store events using AWS Lambda and store them in S3 Access Point - 'inventory_event'"
)

# Store events bucket access points
store_events_bkt_access_points_stack = S3AccessPointsStack(
    app,
    # f"{app.node.try_get_context('project')}-sales-events-bkt-stack",
    f"store-events-bkt-access-points-stack",
    stack_log_level="INFO",
    ec2_s3_ap_name="ec2-consumer",
    ec2_consumer_role=sales_event_consumer_on_ec2._instance_role,
    lambda_s3_ap_name="lambda-consumer",
    lambda_consumer_role=serverless_s3_producer_stack.data_producer_fn_role,
    sales_event_bkt=sales_events_bkt_stack.data_bkt,
    description="Miztiik Automation: Create 'sales_event' & 'inventory_event` bucket access points"
)


# Stack Level Tagging
_tags_lst = app.node.try_get_context("tags")

if _tags_lst:
    for _t in _tags_lst:
        for k, v in _t.items():
            cdk.Tags.of(app).add(k, v, apply_to_launched_instances=True)

app.synth()
