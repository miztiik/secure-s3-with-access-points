from aws_cdk import aws_s3 as _s3
from aws_cdk import core as cdk
from aws_cdk import aws_iam as _iam
from stacks.miztiik_global_args import GlobalArgs


class S3AccessPointsStack(cdk.Stack):

    def __init__(
        self,
        scope: cdk.Construct,
        construct_id: str,
        stack_log_level: str,
        ec2_s3_ap_name:str,
        ec2_consumer_role,
        lambda_s3_ap_name: str,
        lambda_consumer_role,
        sales_event_bkt,
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Create Admin Access Point
        # Admin can access the Bucket ARN - DO NOT NEED ACCESS POINTs

        # Create ec2 Access Point
        ec2_s3_ap_prefix = "sales_event"

        ec2_s3_access_point_policy_doc = {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Principal": {
                        "AWS": f"{ec2_consumer_role.role_arn}"
                    },
                    "Action": ["s3:GetObject", "s3:PutObject"],
                    "Resource": f"arn:aws:s3:{cdk.Aws.REGION}:{cdk.Aws.ACCOUNT_ID}:accesspoint/{ec2_s3_ap_name}/object/{ec2_s3_ap_prefix}/*"
                }
            ]
        }

        ec2_consumer_ap = _s3.CfnAccessPoint(
            self,
            "ec2ConsumerAccessPoint",
            bucket=sales_event_bkt.bucket_name,
            name=f"{ec2_s3_ap_name}",
            policy=ec2_s3_access_point_policy_doc
        )

        # Create lambda Access Point
        lambda_s3_ap_prefix = "inventory_event"
        lambda_s3_access_point_policy_doc = {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Principal": {
                        "AWS": f"{lambda_consumer_role.role_arn}"
                    },
                    "Action": ["s3:GetObject", "s3:PutObject"],
                    "Resource": f"arn:aws:s3:{cdk.Aws.REGION}:{cdk.Aws.ACCOUNT_ID}:accesspoint/{lambda_s3_ap_name}/object/{lambda_s3_ap_prefix}/*"
                }
            ]
        }

        self.lambda_consumer_ap = _s3.CfnAccessPoint(
            self,
            "lambdaConsumerAccessPoint",
            bucket=sales_event_bkt.bucket_name,
            name=f"{lambda_s3_ap_name}",
            policy=lambda_s3_access_point_policy_doc
        )

        ###########################################
        ################# OUTPUTS #################
        ###########################################
        output_0 = cdk.CfnOutput(
            self,
            "AutomationFrom",
            value=f"{GlobalArgs.SOURCE_INFO}",
            description="To know more about this automation stack, check out our github page."
        )

        output_1 = cdk.CfnOutput(
            self,
            "Ec2ConsumerAccessPointArn",
            value=f"arn:aws:s3:{cdk.Aws.REGION}:{cdk.Aws.ACCOUNT_ID}:accesspoint/{ec2_consumer_ap.ref}",
            description=f"The Ec2 consumer access point bucket ARN"
        )

        output_2 = cdk.CfnOutput(
            self,
            "LambdaConsumerAccessPointArn",
            value=f"arn:aws:s3:{cdk.Aws.REGION}:{cdk.Aws.ACCOUNT_ID}:accesspoint/{self.lambda_consumer_ap.ref}",
            description=f"The Lambda consumer access point bucket ARN"
        )
