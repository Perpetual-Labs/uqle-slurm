#!/usr/bin/env bash

# https://gist.github.com/mohanpedala/1e2ff5661761d3abd0385e8223e16425#file-bash_strict_mode-md
set -euo pipefail

#####
# Script arguments
#####
SLURM_JWT_KEY="$1"
# GitHub release tag for UQLE CLI tool
CLI_TAG="$2"
# GitHub OAuth token - should have read access to UQLE CLI releases, and the UQLE stack repository
MACHINE_USER_TOKEN="$3"
UQLE_API_HOST="$4"


# global variables
JWT_KEY_DIR=/var/spool/slurm.state
JWT_KEY_FILE=$JWT_KEY_DIR/jwt_hs256.key
SLURMDBD_USER="slurm"
SLURM_PASSWORD_FILE=/root/slurmdb.password

. /etc/parallelcluster/cfnconfig

echo "Node type: ${cfn_node_type}"

function modify_slurm_conf() {
    # add JWT auth and accounting config to slurm.conf
    # /opt/slurm is shared via nfs, so this only needs to be configured on head node

    cat >> /opt/slurm/etc/slurm.conf <<EOF
# Enable jwt auth for Slurmrestd
AuthAltTypes=auth/jwt
# ACCOUNTING
JobAcctGatherType=jobacct_gather/linux
AccountingStorageType=accounting_storage/slurmdbd
AccountingStoragePort=6819
EOF
}


function configure_users_common() {
    sysctl user.max_user_namespaces=15000
    usermod --add-subuids 165536-231071 --add-subgids 165536-231071 slurm
}

function configure_users_head_node() {
    configure_users_common

    cat << 'EOF' | tee -a /home/centos/.bashrc /home/slurm/.bashrc
# Set variables to avoid podman conflicts between nodes due to nfs-sharing of /home
# See basedir-spec at https://specifications.freedesktop.org/

# If default is undefined or doesn't exist, make a new directory
if [ ! -z "$XDG_RUNTIME_DIR" ] && [ ! -d "$XDG_RUNTIME_DIR" ]; then
    XDG_RUNTIME_DIR=$(mktemp -qd /tmp/$(id -u)-runtime-XXXXXXXXXX)
fi

export XDG_RUNTIME_DIR
export XDG_DATA_HOME=$XDG_RUNTIME_DIR/.local/share && mkdir -p "$XDG_DATA_HOME"
export XDG_STATE_HOME=$XDG_RUNTIME_DIR/.state && mkdir -p "$XDG_STATE_HOME"
export XDG_CACHE_HOME=$XDG_RUNTIME_DIR/.cache && mkdir -p "$XDG_CACHE_HOME"

# Config files can remain common to all nodes
export XDG_CONFIG_HOME=$XDG_RUNTIME_DIR/.config && mkdir -p "$XDG_CONFIG_HOME"

alias podman='podman --runroot="$XDG_RUNTIME_DIR" --root="$XDG_DATA_HOME"'
EOF
}

function write_jwt_key_file() {
    # set the jwt key
    if [ ${SLURM_JWT_KEY} ]
    then
        echo "- JWT secret variable found, writing..."

        mkdir -p $JWT_KEY_DIR

        echo -n ${SLURM_JWT_KEY} > ${JWT_KEY_FILE}
    else
        echo "Error: JWT key not present in environment - aborting cluster deployment" >&2
        return 1
    fi

    chown slurm:slurm $JWT_KEY_FILE
    chmod 0600 $JWT_KEY_FILE
}

function create_slurmrest_conf() {
    # create the slurmrestd.conf file
    # this file can be owned by root, because the slurmrestd service is run by root
    cat > /opt/slurm/etc/slurmrestd.conf <<EOF
include /opt/slurm/etc/slurm.conf
AuthType=auth/jwt
EOF

}

function create_slurmdb_conf() {
    local slurmdbd_password=$(cat "${SLURM_PASSWORD_FILE}")

    # create the slurmdbd.conf file
    cat > /opt/slurm/etc/slurmdbd.conf <<EOF
AuthType=auth/munge
DbdHost=localhost
DebugLevel=info
DbdPort=6819
SlurmUser=slurm
LogFile=/var/log/slurmdbd.log
StorageType=accounting_storage/mysql
StorageUser=${SLURMDBD_USER}
StoragePass=${slurmdbd_password}
StorageHost=localhost
AuthAltTypes=auth/jwt
AuthAltParameters=jwt_key=${JWT_KEY_FILE}
EOF

    chown slurm:slurm /opt/slurm/etc/slurmdbd.conf
    chmod 600 /opt/slurm/etc/slurmdbd.conf
}

function create_slurmrest_service() {

    cat >/etc/systemd/system/slurmrestd.service<<EOF
[Unit]
Description=Slurm restd daemon
After=network.target slurmctld.service
Requires=slurmctld.service
ConditionPathExists=/opt/slurm/etc/slurmrestd.conf

[Service]
Environment=SLURM_CONF=/opt/slurm/etc/slurmrestd.conf
ExecStart=/opt/slurm/sbin/slurmrestd -a rest_auth/jwt -s openapi/v0.0.37 -u slurmrestd -g slurmrestd 0.0.0.0:8082

[Install]
WantedBy=multi-user.target
EOF
}

function create_slurmdb_service() {
    cat >/etc/systemd/system/slurmdbd.service<<EOF
[Unit]
Description=Slurm database daemon
After=network.target
Before=slurmctld.service
ConditionPathExists=/opt/slurm/etc/slurmdbd.conf

[Service]
Environment=SLURM_CONF=/opt/slurm/etc/slurmdbd.conf
ExecStart=/opt/slurm/sbin/slurmdbd -D

[Install]
WantedBy=multi-user.target
RequiredBy=slurmctld.service
EOF
}


function head_node_action() {
    echo "Running head node boot action"

    systemctl disable slurmctld.service
    systemctl stop slurmctld.service

    configure_users_head_node

    write_jwt_key_file

    modify_slurm_conf

    create_slurmrest_conf

    create_slurmdb_conf

    create_slurmrest_service

    create_slurmdb_service

    systemctl daemon-reload
    systemctl enable slurmctld.service slurmrestd.service slurmdbd.service

    systemctl start slurmdbd.service
    sudo -u slurm /opt/slurm/bin/sacctmgr -i add cluster parallelcluster

    systemctl start slurmctld.service slurmrestd.service

    chown slurm:slurm /shared

}

function compute_node_action() {
    echo "Running compute node boot action"
    systemctl disable slurmd.service
    systemctl stop slurmd.service

    configure_users_common

    systemctl enable slurmd.service
    systemctl start slurmd.service
}

if [[ "${cfn_node_type}" == "HeadNode" ]]; then
    head_node_action
elif [[ "${cfn_node_type}" == "ComputeFleet" ]]; then
    compute_node_action
fi
