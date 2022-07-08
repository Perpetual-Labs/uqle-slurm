#!/usr/bin/env bash

# https://gist.github.com/mohanpedala/1e2ff5661761d3abd0385e8223e16425#file-bash_strict_mode-md
set -euxo pipefail


function configure_yum() {
    cat >> /etc/yum.conf <<EOF
assumeyes=1
clean_requirements_on_remove=1
EOF
}

function install_fuse_overlayfs() {
    yum -q install buildah

    mknod /dev/fuse -m 0666 c 10 229

    pushd $(mktemp -d)
    git clone -b dev --depth 1 https://${MACHINE_USER_TOKEN}@github.com/Perpetual-Labs/uqle.git ./uqle
    popd
    https://github.com/containers/fuse-overlayfs.git


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


    configure_users

    configure_yum

    install_head_node_dependencies

    configure_slurm_database

    rebuild_slurm

    write_jwt_key_file

    modify_slurm_conf

    create_slurmrest_conf

    create_slurmdb_conf

    useradd --system --no-create-home -c "slurm rest daemon user" slurmrestd
    create_slurmrest_service

    create_slurmdb_service

    reload_and_enable_services

    chown slurm:slurm /shared

    # install_and_run_gitlab_runner

}

if [[ "${cfn_node_type}" == "HeadNode" ]]; then
    head_node_action
elif [[ "${cfn_node_type}" == "ComputeFleet" ]]; then
    compute_node_action
fi
