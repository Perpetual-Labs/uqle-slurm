#!/usr/bin/env bash

# https://gist.github.com/mohanpedala/1e2ff5661761d3abd0385e8223e16425#file-bash_strict_mode-md
set -euo pipefail

. /etc/parallelcluster/cfnconfig

echo "Node type: $cfn_node_type"

function apt_cleanup() {
    apt-get -qy autoremove
    apt-get -qy clean all
}

function apt_upgrade() {
    apt-get -qy update
    apt-get -qy upgrade
}

function install_go() {
    pushd "$(mktemp -d)"

    local tar_file="go1.18.4.linux-amd64.tar.gz"
    local tar_file_sha="c9b099b68d93f5c5c8a8844a89f8db07eaa58270e3a1e01804f17f4cf8df02f5"

    wget "https://go.dev/dl/$tar_file"
    rm -rf /usr/local/go
    tar -C /usr/local -xzf "$tar_file"

    # check SHA256
    echo "$tar_file_sha $tar_file" | sha256sum -c

    export PATH="$PATH:/usr/local/go/bin"
    echo "export PATH=\$PATH:/usr/local/go/bin" >>/etc/profile

    popd
}

function build_and_install_podman() {

    apt-get -qy install btrfs-progs git go-md2man iptables libassuan-dev libbtrfs-dev libc6-dev libdevmapper-dev libglib2.0-dev libgpgme-dev libgpg-error-dev libprotobuf-dev libprotobuf-c-dev libseccomp-dev libselinux1-dev libsystemd-dev pkg-config runc uidmap

    pushd "$(mktemp -d)"

    local version_tag="v4.1.1"
    git clone --branch "$version_tag" --single-branch --depth 1 https://github.com/containers/podman ./podman

    cd podman
    make BUILDTAGS="selinux seccomp"
    make install PREFIX=/usr

    popd
}

function install_fuse_overlayfs() {

    apt-get -qy install buildah fuse3

    pushd "$(mktemp -d)"

    local version_tag="v1.9"
    git clone --branch "$version_tag" --single-branch --depth 1 https://github.com/containers/fuse-overlayfs.git ./fuse-overlayfs
    cd fuse-overlayfs

    buildah bud -v "$PWD:/build/fuse-overlayfs" -t fuse-overlayfs -f ./Containerfile.static.ubuntu .

    cp fuse-overlayfs /usr/bin/

    popd

}

function install_podman() {
    apt-get -qy install slirp4netns

    install_fuse_overlayfs

    install_go

    build_and_install_podman

}

function enable_user_namespaces() {
    sysctl kernel.unprivileged_userns_clone=1
    echo 'kernel.unprivileged_userns_clone=1' >/etc/sysctl.d/userns.conf
}

function install_head_node_dependencies() {

    # MariaDB repository setup
    curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | bash

    . /etc/os-release
    echo "deb http://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/xUbuntu_${VERSION_ID}/ /" >/etc/apt/sources.list.d/devel:kubic:libcontainers:stable.list
    wget -nv "https://download.opensuse.org/repositories/devel:kubic:libcontainers:stable/xUbuntu_${VERSION_ID}/Release.key" -O- | apt-key add -

    apt_upgrade

    # mariadb
    apt-get -qy install mariadb-server

    # podman
    install_podman

    apt_cleanup
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

    apt_upgrade

    install_podman

    apt_cleanup
}

function compute_node_action() {
    echo "Running compute node boot action"

    install_compute_node_dependencies

    enable_user_namespaces

}

function head_node_action() {
    echo "Running head node boot action"

    useradd --system --no-create-home -c "slurm rest daemon user" slurmrestd

    install_head_node_dependencies

    enable_user_namespaces

    configure_slurm_database

}

if [[ "${cfn_node_type}" == "HeadNode" ]]; then
    head_node_action
elif [[ "${cfn_node_type}" == "ComputeFleet" ]]; then
    compute_node_action
fi
