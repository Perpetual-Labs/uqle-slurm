#!/usr/bin/env bash

# https://gist.github.com/mohanpedala/1e2ff5661761d3abd0385e8223e16425#file-bash_strict_mode-md
set -euxo pipefail

. /etc/parallelcluster/cfnconfig

echo "Node type: ${cfn_node_type}"

function configure_yum() {
    cat >> /etc/yum.conf <<EOF
assumeyes=1
clean_requirements_on_remove=1
EOF
}

function install_fuse_overlayfs() {
    yum -q install buildah

    if [[ ! -e /dev/fuse ]]; then
        mknod /dev/fuse -m 0666 c 10 229
    fi

    pushd $(mktemp -d)
    git clone --depth 1 https://github.com/containers/fuse-overlayfs.git ./overlay
    pushd ./overlay
    buildah bud -v $PWD:/build/fuse-overlayfs -t fuse-overlayfs -f ./Containerfile.static.ubuntu .
    cp fuse-overlayfs /usr/bin/

}

function yum_cleanup() {
    yum -q clean all
    rm -rf /var/cache/yum
}

function install_head_node_dependencies() {
    # MariaDB repository setup
    curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | bash

    yum_cleanup

    yum -q update

    yum -q install epel-release
    yum-config-manager -y --enable epel
    # Slurm build deps
    yum -q install libyaml-devel libjwt-devel http-parser-devel json-c-devel
    # Pyenv build deps
    yum -q install gcc zlib-devel bzip2 bzip2-devel readline-devel sqlite sqlite-devel openssl-devel tk-devel libffi-devel xz-devel
    # mariadb
    yum -q install MariaDB-server

    # podman
    yum -q install fuse-overlayfs slirp4netns podman

    # Install go-task, see https://taskfile.dev/install.sh
    sh -c "$(curl --location https://taskfile.dev/install.sh)" -- -d -b /usr/local/bin

    yum_cleanup
}

function create_and_save_slurmdb_password() {
    if [[ -e "$SLURM_PASSWORD_FILE" ]]; then
        echo "Error: create_and_save_slurmdb_password() was called when a password file already exists" >&2
        return 1
    fi

    echo -n $(pwmake 128) > $SLURM_PASSWORD_FILE
}

function configure_slurm_database() {

    systemctl enable mariadb.service
    systemctl start mariadb.service

    create_and_save_slurmdb_password

    local slurmdbd_password=$(cat "${SLURM_PASSWORD_FILE}")

    mysql --wait -e "CREATE USER '${SLURMDBD_USER}'@'localhost' identified by '${slurmdbd_password}'"
    mysql --wait -e "GRANT ALL ON *.* to '${SLURMDBD_USER}'@'localhost' identified by '${slurmdbd_password}' with GRANT option"
}

function install_compute_node_dependencies() {
    yum_cleanup

    yum -q update

    yum -q install podman

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
