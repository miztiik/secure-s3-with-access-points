#!/bin/bash
set -ex
set -o pipefail

# version: 04Aug2020

##################################################
#############     SET GLOBALS     ################
##################################################

# Troubleshoot here
# /var/lib/cloud/instance/scripts/part-001:
# /var/log/user-data.log

REPO_NAME="mysql-to-rds"

GIT_REPO_URL="https://github.com/miztiik/$REPO_NAME.git"

APP_DIR="/var/$REPO_NAME"

# Send logs to console
# exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1



instruction()
{
  echo "usage: ./build.sh package <stage> <region>"
  echo ""
  echo "/build.sh deploy <stage> <region> <pkg_dir>"
  echo ""
  echo "/build.sh test-<test_type> <stage>"
}

assume_role() {
  if [ -n "$DEPLOYER_ROLE_ARN" ]; then
    echo "Assuming role $DEPLOYER_ROLE_ARN ..."
    CREDS=$(aws sts assume-role --role-arn $DEPLOYER_ROLE_ARN \
        --role-session-name my-sls-session --out json)
    echo $CREDS > temp_creds.json
    export AWS_ACCESS_KEY_ID=$(node -p "require('./temp_creds.json').Credentials.AccessKeyId")
    export AWS_SECRET_ACCESS_KEY=$(node -p "require('./temp_creds.json').Credentials.SecretAccessKey")
    export AWS_SESSION_TOKEN=$(node -p "require('./temp_creds.json').Credentials.SessionToken")
    aws sts get-caller-identity
  fi
}

unassume_role() {
  unset AWS_ACCESS_KEY_ID
  unset AWS_SECRET_ACCESS_KEY
  unset AWS_SESSION_TOKEN
}

function install_xray(){
    # Install AWS XRay Daemon for telemetry
    curl https://s3.dualstack.us-east-2.amazonaws.com/aws-xray-assets.us-east-2/xray-daemon/aws-xray-daemon-3.x.rpm -o /home/ec2-user/xray.rpm
    yum install -y /home/ec2-user/xray.rpm
}

function install_nginx(){
    echo 'Begin NGINX Installation'
    sudo amazon-linux-extras install -y nginx1.12
    sudo systemctl start nginx
}

function clone_git_repo(){
    install_libs
    # mkdir -p /var/
    cd /var
    git clone $GIT_REPO_URL

}

function add_env_vars(){
    EC2_AVAIL_ZONE=`curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone`
    AWS_REGION="`echo \"$EC2_AVAIL_ZONE\" | sed 's/[a-z]$//'`"
    export AWS_REGION
    sudo touch /var/log/miztiik-load-generator-unthrottled.log
    sudo touch /var/log/miztiik-load-generator-throttled.log
    sudo chmod 775 /var/log/miztiik-load-generator-*
    sudo chown root:ssm-user /var/log/miztiik-load-generator-*
}

function install_libs(){
    # Prepare the server for python3
    yum -y install python-pip python3 git
    yum install -y jq
    pip3 install boto3
}

function install_nodejs(){
    # https://docs.aws.amazon.com/sdk-for-javascript/v2/developer-guide/setting-up-node-on-ec2-instance.html
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.34.0/install.sh | bash
    . ~/.nvm/nvm.sh
    nvm install node
    node -e "console.log('Running Node.js ' + process.version)"
}

function install_mysqldb(){
# sudo wget https://archive.mariadb.org//mariadb-10.3.13/yum/centos8-amd64/rpms/MariaDB-server-10.3.13-1.el8.x86_64.rpm

#baseurl = http://yum.mariadb.org/10.3/centos7-amd64

sudo tee /etc/yum.repos.d/mariadb.repo<<EOF
[mariadb]
name = MariaDB
baseurl = http://yum.mariadb.org/10.2/centos7-amd64/
gpgkey=https://yum.mariadb.org/RPM-GPG-KEY-MariaDB
gpgcheck=1
EOF

sudo yum install -y mariadb-server
sudo systemctl start mariadb
sudo systemctl enable mariadb
pip3 install mysql-connector-python
# sudo wget https://dev.mysql.com/get/mysql57-community-release-el7-11.noarch.rpm
# sudo yum localinstall mysql57-community-release-el7-11.noarch.rpm 
# sudo yum install mysql-community-server



}

function configure_mysqldb(){



# Resetting Root Password
# https://dev.mysql.com/doc/refman/8.0/en/resetting-permissions.html

DATABASE_PASS="Som3thingSh0uldBe1nVault"
mysqladmin -u root password "$DATABASE_PASS"
mysql -u root -p"$DATABASE_PASS" -e "UPDATE mysql.user SET Password=PASSWORD('$DATABASE_PASS') WHERE User='root'"
mysql -u root -p"$DATABASE_PASS" -e "GRANT ALL ON *.* TO 'root'@'%' IDENTIFIED BY '$DATABASE_PASS' WITH GRANT OPTION;"
# mysql -u root -p"$DATABASE_PASS" -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1')"
mysql -u root -p"$DATABASE_PASS" -e "DELETE FROM mysql.user WHERE User=''"
mysql -u root -p"$DATABASE_PASS" -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\_%'"
mysql -u root -p"$DATABASE_PASS" -e "CREATE USER 'mysqladmin'@'%' IDENTIFIED BY '$DATABASE_PASS'"
mysql -u root -p"$DATABASE_PASS" -e "GRANT ALL PRIVILEGES ON db.* TO mysqladmin @'%' IDENTIFIED BY '$DATABASE_PASS'"
mysql -u root -p"$DATABASE_PASS" -e "GRANT ALL PRIVILEGES ON * . * TO 'mysqladmin'@'%'"
mysql -u root -p"$DATABASE_PASS" -e "FLUSH PRIVILEGES"
mysql -u root -p"$DATABASE_PASS" -e "CREATE USER 'replication_user'@'%' IDENTIFIED BY '$DATABASE_PASS'"
mysql -u root -p"$DATABASE_PASS" -e "GRANT REPLICATION SLAVE ON *.* TO 'replication_user'@'%'"
mysql -u root -p"$DATABASE_PASS" -e "SET GLOBAL binlog_format = 'ROW'"

# Check MySQL Version
mysql -u root -p"$DATABASE_PASS" -e "SHOW VARIABLES LIKE '%version%'"
sudo systemctl restart mariadb


sudo systemctl stop mariadb
# Enabling MYSQL Public Access
sed -i 's/#bind-address=0.0.0.0/bind-address=0.0.0.0/' /etc/my.cnf.d/server.cnf
# sed -i "s/bind-address.*/bind-address = 0.0.0.0/" /etc/mysql/my.cnf
sudo systemctl start mariadb

# SHOW MASTER STATUS;

# Enabling Replication
# https://mariadb.com/kb/en/setting-up-replication/
# /var/lib/mysql
sudo systemctl stop mariadb
cat > '/etc/my.cnf' << "EOF"
[mariadb]
log-bin
server_id=1
log-basename=miztiik_master1
binlog_rows_query_log_events=ON
binlog_row_image=MINIMAL
binlog_format=ROW
EOF
sudo systemctl restart mariadb

mysql -u root -p"$DATABASE_PASS" -e "SHOW MASTER STATUS"
mysql -u root -p"$DATABASE_PASS" -e "FLUSH PRIVILEGES"

# List 10 rows
# mysql -u root -p"$DATABASE_PASS" -e "use miztiik_db;SELECT * FROM customers LIMIT 10;"
# mysql -u root -p"$DATABASE_PASS" -e "use miztiik_db;SELECT COUNT(*) FROM customers;"

}


function install_cw_agent() {
# Installing AWS CloudWatch Agent FOR AMAZON LINUX RPM
agent_dir="/tmp/cw_agent"
cw_agent_rpm="https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm"
mkdir -p ${agent_dir} \
    && cd ${agent_dir} \
    && sudo yum install -y curl \
    && curl ${cw_agent_rpm} -o ${agent_dir}/amazon-cloudwatch-agent.rpm \
    && sudo rpm -U ${agent_dir}/amazon-cloudwatch-agent.rpm


cw_agent_schema="/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json"

# PARAM_NAME="/stream-data-processor/streams/data_pipe/stream_name"
# a=$(aws ssm get-parameter --name "$PARAM_NAME" --with-decryption --query "Parameter.{Value:Value}" --output text)
# LOG_GROUP_NAME="/stream-data-processor/producers"

cat > '/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json' << "EOF"
{
"agent": {
    "metrics_collection_interval": 5,
    "logfile": "/opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log"
},
"metrics": {
    "metrics_collected": {
    "mem": {
        "measurement": [
        "mem_used_percent"
        ]
    }
    },
    "append_dimensions": {
    "ImageId": "${aws:ImageId}",
    "InstanceId": "${aws:InstanceId}",
    "InstanceType": "${aws:InstanceType}"
    },
    "aggregation_dimensions": [
    [
        "InstanceId",
        "InstanceType"
    ],
    []
    ]
},
"logs": {
    "logs_collected": {
    "files": {
        "collect_list": [
        {
            "file_path": "/var/log/miztiik-automation**.log",
            "log_group_name": "/miztiik-automation",
            "timestamp_format": "%b %-d %H:%M:%S",
            "timezone": "Local"
        }
        ]
    }
    },
    "log_stream_name": "{instance_id}"
}
}
EOF

    # Configure the agent to monitor ssh log file
    sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:${cw_agent_schema} -s
    # Start the CW Agent
    sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -m ec2 -a status

    # Just in case we need to troubleshoot
    # cd "/opt/aws/amazon-cloudwatch-agent/logs/"
}

# Let the execution begin
# if [ $# -eq 0 ]; then
#   instruction
#   exit 1

install_libs
install_mysqldb
configure_mysqldb
install_cw_agent

