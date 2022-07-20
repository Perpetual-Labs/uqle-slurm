#!/usr/bin/env bash

# https://gist.github.com/mohanpedala/1e2ff5661761d3abd0385e8223e16425#file-bash_strict_mode-md
set -euo pipefail

. /etc/parallelcluster/cfnconfig

echo "Node type: ${cfn_node_type}"

function configure_yum() {
    cat >>/etc/yum.conf <<EOF
assumeyes=1
clean_requirements_on_remove=1
EOF
}

function yum_cleanup() {
    yum -q clean all
    rm -rf /var/cache/yum
}
function install_podman() {
    yum -q install fuse-overlayfs slirp4netns podman
}

function install_head_node_dependencies() {
    # MariaDB repository setup
    curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | bash

    yum_cleanup

    yum -q update

    yum -q install epel-release
    yum-config-manager -y --enable epel

    # mariadb
    yum -q install MariaDB-server

    # podman
    install_podman

    # Install go-task, see https://taskfile.dev/install.sh
    sh -c "$(curl --location https://taskfile.dev/install.sh)" -- -d -b /usr/local/bin

    yum_cleanup
}

function create_and_save_slurmdb_password() {
    local slurm_password_file="/root/slurmdb.password"
    if [[ -e "$slurm_password_file" ]]; then
        echo "Error: create_and_save_slurmdb_password() was called when a password file already exists" >&2
        return 1
    fi

    echo -n "$(openssl rand -hex 32)" >"$slurm_password_file"
}

function configure_slurm_database() {

    systemctl enable mariadb.service
    systemctl start mariadb.service

    create_and_save_slurmdb_password

    local slurmdbd_password
    slurmdbd_password="$(cat /root/slurmdb.password)"

    local slurmdbd_user="slurm"
    local slurmdb_name="slurm_acct_db"

    mysql --wait -e "CREATE USER '${slurmdbd_user}'@'localhost' identified by '${slurmdbd_password}'"
    mysql --wait -e "CREATE DATABASE ${slurmdb_name}"
    mysql --wait -e "GRANT ALL ON ${slurmdb_name}.* to '${slurmdbd_user}'@'localhost' identified by '${slurmdbd_password}'"
}

function install_compute_node_dependencies() {
    yum_cleanup

    yum -q update

    install_podman

    yum_cleanup
}

function compute_node_action() {
    echo "Running compute node boot action"
    configure_yum
    install_compute_node_dependencies
    # TODO overlayfs

}

function head_node_action() {
    echo "Running head node boot action"

    sysctl user.max_user_namespaces=15000

    useradd --system --no-create-home -c "slurm rest daemon user" slurmrestd

    configure_yum

    install_head_node_dependencies
    # TODO overlayfs

    configure_slurm_database

}

if [[ "${cfn_node_type}" == "HeadNode" ]]; then
    head_node_action
elif [[ "${cfn_node_type}" == "ComputeFleet" ]]; then
    compute_node_action
fi
