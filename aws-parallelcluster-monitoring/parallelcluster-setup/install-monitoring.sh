#!/bin/bash -ix
#
#
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
#
#

#source the AWS ParallelCluster profile
. /etc/parallelcluster/cfnconfig

# Install Docker
sudo apt-get update
sudo apt-get install \
    ca-certificates \
    curl \
    gnupg \
    lsb-release
sudo mkdir -m 0755 -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update

sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y




curl -L "https://github.com/docker/compose/releases/download/1.27.4/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

monitoring_dir_name=aws-parallelcluster-monitoring
monitoring_home="/home/${cfn_cluster_user}/${monitoring_dir_name}"

echo "$> variable monitoring_dir_name -> ${monitoring_dir_name}"
echo "$> variable monitoring_home -> ${monitoring_home}"

# Retrieve metadata token
TOKEN=`curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"`


case "${cfn_node_type}" in
	HeadNode)

		cfn_fsx_lustre_id=$(grep lustre /etc/fstab | cut -d. -f1)
		master_instance_id=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/instance-id)
		cfn_max_queue_size=$(aws cloudformation describe-stacks --stack-name $stack_name --region $cfn_region | jq -r '.Stacks[0].Parameters | map(select(.ParameterKey == "MaxSize"))[0].ParameterValue')
		s3_bucket=$(echo $cfn_postinstall | sed "s/s3:\/\///g;s/\/.*//")
		cluster_s3_bucket=$(cat /etc/chef/dna.json | grep \"cluster_s3_bucket\" | awk '{print $2}' | sed "s/\",//g;s/\"//g")
		cluster_config_s3_key=$(cat /etc/chef/dna.json | grep \"cluster_config_s3_key\" | awk '{print $2}' | sed "s/\",//g;s/\"//g")
		cluster_config_version=$(cat /etc/chef/dna.json | grep \"cluster_config_version\" | awk '{print $2}' | sed "s/\",//g;s/\"//g")
		log_group_names="$(aws cloudformation describe-stack-resource --stack-name ${stack_name} --logical-resource-id CloudWatchLogGroup --region $cfn_region --query StackResourceDetail.PhysicalResourceId --output text)"

		aws s3api get-object --bucket $cluster_s3_bucket --key $cluster_config_s3_key --region $cfn_region --version-id $cluster_config_version ${monitoring_home}/parallelcluster-setup/cluster-config.json

		apt -y update
		apt -y install golang
		apt -y install python3-setuptools python3-boto3 

		chown $cfn_cluster_user:$cfn_cluster_user -R /home/$cfn_cluster_user
		chmod +x ${monitoring_home}/custom-metrics/*

		cp -rp ${monitoring_home}/custom-metrics/* /usr/local/bin/
		mv ${monitoring_home}/prometheus-slurm-exporter/slurm_exporter.service /etc/systemd/system/

	 	(crontab -l -u $cfn_cluster_user; echo "*/1 * * * * /usr/local/bin/1m-cost-metrics.sh") | crontab -u $cfn_cluster_user -
		(crontab -l -u $cfn_cluster_user; echo "*/60 * * * * /usr/local/bin/1h-cost-metrics.sh") | crontab -u $cfn_cluster_user -
		
		# replace region
		sed -i "s/us-east-1/$cfn_region/g"                          ${monitoring_home}/prometheus/prometheus.yml
		sed -i "s/us-east-1/$cfn_region/g"                          ${monitoring_home}/custom-metrics/1h-cost-metrics.sh
		sed -i "s/us-east-1/$cfn_region/g"                          ${monitoring_home}/custom-metrics/1m-cost-metrics.sh

		# replace tokens
		sed -i "s/_S3_BUCKET_/${s3_bucket}/g"               	${monitoring_home}/grafana/dashboards/ParallelCluster.json
		sed -i "s/__INSTANCE_ID__/${master_instance_id}/g"  	${monitoring_home}/grafana/dashboards/ParallelCluster.json
		sed -i "s/__FSX_LUSTRE_ID__/${cfn_fsx_lustre_id}/g"     ${monitoring_home}/grafana/dashboards/ParallelCluster.json
		sed -i "s/__AWS_REGION__/${cfn_region}/g"           	${monitoring_home}/grafana/dashboards/ParallelCluster.json

		sed -i "s/__AWS_REGION__/${cfn_region}/g"           	${monitoring_home}/grafana/dashboards/logs.json
		sed -i "s|__LOG_GROUP__NAMES__|${log_group_names}|g"    ${monitoring_home}/grafana/dashboards/logs.json

		sed -i "s/__Application__/${stack_name}/g"          	${monitoring_home}/prometheus/prometheus.yml

		sed -i "s/__INSTANCE_ID__/${master_instance_id}/g"  	${monitoring_home}/grafana/dashboards/head-node-details.json
		sed -i "s/__INSTANCE_ID__/${master_instance_id}/g"  	${monitoring_home}/grafana/dashboards/compute-node-list.json
		sed -i "s/__INSTANCE_ID__/${master_instance_id}/g"  	${monitoring_home}/grafana/dashboards/compute-node-details.json
                sed -i "s/__INSTANCE_ID__/${master_instance_id}/g"      ${monitoring_home}/grafana/dashboards/jobs-details.json

		sed -i "s/__MONITORING_DIR__/${monitoring_dir_name}/g"  ${monitoring_home}/docker-compose/docker-compose.head.yml

		#Generate selfsigned certificate for Nginx over ssl
		nginx_dir="${monitoring_home}/nginx"
		nginx_ssl_dir="${nginx_dir}/ssl"
		mkdir -p ${nginx_ssl_dir}
		echo -e "\nDNS.1=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/local-hostname)" >> "${nginx_dir}/openssl.cnf"
		openssl req -new -x509 -nodes -newkey rsa:4096 -days 3650 -keyout "${nginx_ssl_dir}/nginx.key" -out "${nginx_ssl_dir}/nginx.crt" -config "${nginx_dir}/openssl.cnf"

		#give $cfn_cluster_user ownership
		chown -R $cfn_cluster_user:$cfn_cluster_user "${nginx_ssl_dir}/nginx.key"
		chown -R $cfn_cluster_user:$cfn_cluster_user "${nginx_ssl_dir}/nginx.crt"
		
		# Download Docker images for compute nodes
		docker pull quay.io/prometheus/node-exporter
		docker pull nvidia/dcgm-exporter
		docker save quay.io/prometheus/node-exporter > /opt/parallelcluster/shared/node-exporter.tar
		docker save nvidia/dcgm-exporter > /opt/parallelcluster/shared/dcgm-exporter.tar

		/usr/local/bin/docker-compose --env-file /etc/parallelcluster/cfnconfig -f ${monitoring_home}/docker-compose/docker-compose.head.yml -p monitoring-master up -d

		# Download and build prometheus-slurm-exporter
		##### Plese note this software package is under GPLv3 License #####
		# More info here: https://github.com/vpenso/prometheus-slurm-exporter/blob/master/LICENSE
		cd ${monitoring_home}
		git clone --branch development https://github.com/vpenso/prometheus-slurm-exporter.git
        export HOME=/root
        git config --global --add safe.directory ${monitoring_home}/prometheus-slurm-exporter
		cd prometheus-slurm-exporter
        sed -i 's/NodeList,AllocMem,Memory,CPUsState,StateLong/NodeList: ,AllocMem: ,Memory: ,CPUsState: ,StateLong:/' node.go
		GOPATH=/root/go-modules-cache HOME=/root go mod download
		GOPATH=/root/go-modules-cache HOME=/root go build
		mv ${monitoring_home}/prometheus-slurm-exporter/prometheus-slurm-exporter /usr/bin/prometheus-slurm-exporter

		systemctl daemon-reload
		systemctl enable slurm_exporter
		systemctl start slurm_exporter

                # create job tagging script for cronjob
                cat <<CHECKTAGS_EOF > /opt/slurm/sbin/check_tags.sh
#!/bin/bash
source /etc/profile

update=0
tag_userid=""
tag_jobid=""

TOKEN=`curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"`

if [ ! -f /tmp/jobs/jobs_users ] || [ ! -f /tmp/jobs/jobs_ids ]; then
  exit 0
fi

active_users=\$(cat /tmp/jobs/jobs_users | sort | uniq )
active_jobs=\$(cat /tmp/jobs/jobs_ids | sort )
echo \$active_users > /tmp/jobs/tmp_jobs_users
echo \$active_jobs > /tmp/jobs/tmp_jobs_ids

if [ ! -f /tmp/jobs/tag_userid ] || [ ! -f /tmp/jobs/tag_jobid ]; then
  echo \$active_users > /tmp/jobs/tag_userid
  echo \$active_jobs > /tmp/jobs/tag_jobid
  update=1
else
  active_users=\$(cat /tmp/jobs/tmp_jobs_users)
  active_jobs=\$(cat /tmp/jobs/tmp_jobs_ids)
  tag_userid=\$(cat /tmp/jobs/tag_userid)
  tag_jobid=\$(cat /tmp/jobs/tag_jobid)
  
  if [ "\$active_users" != "\$tag_userid" ]; then
    tag_userid="\$active_users"
    echo \$tag_userid > /tmp/jobs/tag_userid
    update=1
  fi
  
  if [ "\$active_jobs" != "\$tag_jobid" ]; then
    tag_jobid="\$active_jobs"
    echo \$tag_jobid > /tmp/jobs/tag_jobid
    update=1
  fi
fi

if [ \$update -eq 1 ]; then
  # Instance ID
  MyInstID=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/instance-id)
  tag_userid=\$(cat /tmp/jobs/tag_userid)
  tag_jobid=\$(cat /tmp/jobs/tag_jobid)
  aws ec2 create-tags --resources \$MyInstID --tags Key=UserID,Value="\$tag_userid" --region=$cfn_region
  aws ec2 create-tags --resources \$MyInstID --tags Key=JobID,Value="\$tag_jobid" --region=$cfn_region
  
fi
CHECKTAGS_EOF
                chmod +x /opt/slurm/sbin/check_tags.sh
                # Create prolog and epilog to tag the instances
                cat << PROLOG_EOF > /opt/slurm/sbin/prolog.sh
#!/bin/bash
[ ! -d "/tmp/jobs" ] && mkdir -p /tmp/jobs
echo "\$SLURM_JOB_USER" >> /tmp/jobs/jobs_users
echo "\$SLURM_JOBID" >> /tmp/jobs/jobs_ids
PROLOG_EOF

                cat << EPILOG_EOF > /opt/slurm/sbin/epilog.sh
#!/bin/bash
sed -i "0,/\$SLURM_JOB_USER/d" /tmp/jobs/jobs_users
sed -i "0,/\$SLURM_JOBID/d" /tmp/jobs/jobs_ids
EPILOG_EOF

                chmod +x /opt/slurm/sbin/prolog.sh /opt/slurm/sbin/epilog.sh

                #Configure slurm to use Prolog and Epilog
                echo "PrologFlags=Alloc" >> /opt/slurm/etc/slurm.conf
                echo "Prolog=/opt/slurm/sbin/prolog.sh" >> /opt/slurm/etc/slurm.conf
                echo "Epilog=/opt/slurm/sbin/epilog.sh" >> /opt/slurm/etc/slurm.conf
                systemctl restart slurmctld
	;;

	ComputeFleet)
		compute_instance_type=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/instance-type)
		gpu_instances="[pg][2-9].*\.[0-9]*[x]*large"
		echo "$> Compute Instances Type EC2 -> ${compute_instance_type}"
		echo "$> GPUS Instances EC2 -> ${gpu_instances}"
                docker load < /opt/parallelcluster/shared/node-exporter.tar
		if [[ $compute_instance_type =~ $gpu_instances ]]; then
			distribution=$(. /etc/os-release;echo $ID$VERSION_ID) && curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg && curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
			sudo apt-get update
			sudo apt-get install -y nvidia-container-toolkit
			sudo nvidia-ctk runtime configure --runtime=docker
			systemctl restart docker
			docker load < /opt/parallelcluster/shared/dcgm-exporter.tar
			/usr/local/bin/docker-compose -f /home/${cfn_cluster_user}/${monitoring_dir_name}/docker-compose/docker-compose.compute.gpu.yml -p monitoring-compute up -d
        else
			/usr/local/bin/docker-compose -f /home/${cfn_cluster_user}/${monitoring_dir_name}/docker-compose/docker-compose.compute.yml -p monitoring-compute up -d
        fi
        # install job tagging
        mkdir /tmp/jobs
        (crontab -l 2>/dev/null; echo "* * * * * /opt/slurm/sbin/check_tags.sh") | crontab -
	;;
esac
