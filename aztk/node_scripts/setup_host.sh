#!/bin/bash

# Entry point for the start task. It will install all dependencies and start docker.
# Usage:
# setup_host.sh [container_name] [docker_repo_name]
set -e

export AZTK_WORKING_DIR=/mnt/batch/tasks/startup/wd
export PYTHONUNBUFFERED=TRUE

container_name=$1
docker_repo_name=$2

echo "Installing pre-reqs"
apt-get -y update
apt-get install -y --no-install-recommends linux-image-extra-$(uname -r) linux-image-extra-virtual
apt-get install -y --no-install-recommends apt-transport-https
apt-get install -y --no-install-recommends curl
apt-get install -y --no-install-recommends ca-certificates
apt-get install -y --no-install-recommends software-properties-common
apt-get install -y --no-install-recommends python3-pip python3-venv python-dev build-essential libssl-dev
echo "Done installing pre-reqs"

# Install docker
echo "Installing Docker"
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
apt-get -y update
apt-get -y install docker-ce
echo "Done installing Docker"

# set hostname in /etc/hosts if dns cannot resolve
if ! host $HOSTNAME ; then
    echo $(hostname -I | awk '{print $1}') $HOSTNAME >> /etc/hosts
fi

# Install docker-compose
echo "Installing Docker-Componse"
sudo curl -L https://github.com/docker/compose/releases/download/1.19.0/docker-compose-`uname -s`-`uname -m` -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
echo "Done installing Docker-Compose"

if [ $AZTK_GPU_ENABLED == "true" ]; then
    echo "running nvidia install"
    sudo apt-get -y install nvidia-384
    sudo apt-get -y install nvidia-modprobe

    wget -P /tmp https://github.com/NVIDIA/nvidia-docker/releases/download/v1.0.1/nvidia-docker_1.0.1-1_amd64.deb
    sudo dpkg -i /tmp/nvidia-docker*.deb && rm /tmp/nvidia-docker*.deb
    echo "nvidia install complete"
fi

if [ -z "$DOCKER_USERNAME" ]; then
    echo "No Credentials provided. No need to login to dockerhub"
else
    echo "Docker credentials provided. Login in."
    docker login $DOCKER_ENDPOINT --username $DOCKER_USERNAME --password $DOCKER_PASSWORD
fi

echo "Pulling $docker_repo_name"
(time docker pull $docker_repo_name) 2>&1

# Unzip resource files and set permissions
apt-get -y install unzip
chmod 777 $AZTK_WORKING_DIR/aztk/node_scripts/docker_main.sh

# Check docker is running
docker info > /dev/null 2>&1
if [ $? -ne 0 ]; then
  echo "UNKNOWN - Unable to talk to the docker daemon"
  exit 3
fi

echo "Node python version:"
python3 --version

# set up aztk python environment
export LC_ALL=C.UTF-8
export LANG=C.UTF-8
python3 -m pip install pipenv
mkdir -p $AZTK_WORKING_DIR/.aztk-env
cp $AZTK_WORKING_DIR/aztk/node_scripts/Pipfile $AZTK_WORKING_DIR/.aztk-env
cp $AZTK_WORKING_DIR/aztk/node_scripts/Pipfile.lock $AZTK_WORKING_DIR/.aztk-env
cd $AZTK_WORKING_DIR/.aztk-env
export PIPENV_VENV_IN_PROJECT=true
pipenv install --python /usr/bin/python3.5m
pipenv run pip install --upgrade setuptools wheel #TODO: add pip when pipenv is compatible with pip10

# Install python dependencies
$AZTK_WORKING_DIR/.aztk-env/.venv/bin/pip install -r $(dirname $0)/requirements.txt
export PYTHONPATH=$PYTHONPATH:$AZTK_WORKING_DIR

# If the container already exists just restart. Otherwise create it
if [ "$(docker ps -a -q -f name=$container_name)" ]; then
    echo "Docker container is already setup. Restarting it."
    docker restart $container_name
else
    echo "Creating docker container."
  
    echo "Running setup python script"
    $AZTK_WORKING_DIR/.aztk-env/.venv/bin/python $(dirname $0)/main.py setup-node $docker_repo_name

    # wait until container is running
    until [ "`/usr/bin/docker inspect -f {{.State.Running}} $container_name`"=="true" ]; do
        sleep 0.1;
    done;

    # wait until container setup is complete
    echo "Waiting for spark docker container to setup."
    docker exec spark /bin/bash -c '$AZTK_WORKING_DIR/.aztk-env/.venv/bin/python $AZTK_WORKING_DIR/aztk/node_scripts/wait_until_setup_complete.py'

    # Setup symbolic link for the docker logs
    docker_log=$(docker inspect --format='{{.LogPath}}' $container_name)
    mkdir -p $AZ_BATCH_TASK_WORKING_DIR/logs
    ln -s $docker_log $AZ_BATCH_TASK_WORKING_DIR/logs/docker.log
fi
