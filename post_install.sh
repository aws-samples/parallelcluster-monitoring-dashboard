#!/bin/bash
#
#
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
#
#


. "/etc/parallelcluster/cfnconfig"

script_bucket=$(dirname $(grep Script /opt/parallelcluster/shared/cluster-config.yaml | head -1 | awk -F's3://' '{print $2}'))

PATH=$PATH:/opt/slurm/bin

TOKEN=`curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"`

region=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r .region)

case $cfn_node_type in
    HeadNode)
      # download, run monitoring
      aws s3 cp --recursive s3://${script_bucket}/aws-parallelcluster-monitoring /home/ubuntu/aws-parallelcluster-monitoring
      chmod +x /home/ubuntu/aws-parallelcluster-monitoring/parallelcluster-setup/install-monitoring.sh
      /home/ubuntu/aws-parallelcluster-monitoring/parallelcluster-setup/install-monitoring.sh > /tmp/monitoring-setup.log 2>&1
    ;;
    ComputeFleet)
      /home/ubuntu/aws-parallelcluster-monitoring/parallelcluster-setup/install-monitoring.sh > /tmp/monitoring-setup.log 2>&1
      exit 0
    ;;
esac

