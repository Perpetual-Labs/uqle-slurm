# Configure AWS ParallelCluster
Scripts to configure and create a Slurm cluster using [AWS ParallelCluster](https://docs.aws.amazon.com/parallelcluster/latest/ug/install.html).

## Requirements
1. [Install](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) and [configure](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-configure.html) aws-cli
2. [Poetry](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-configure.html)
3. Create a [private key pair](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/create-key-pairs.html) in AWS EC2, and import it to your local filesystem.

## Local set up
### Install dependencies

The ParallelCluster (PC) CLI tool is distributed as a Python package.
To spin up an environment that contains the PC CLI tool and other necessary tools, run:


```bash
# If you'd prefer to manage environments with another tool, just activate an environment before running this command
# Poetry will detect an existing environment and use that rather than creating a new one
poetry install

# Alternatively, if you do not need dev requirements, you can run
poetry install --no-dev
```
This should give you access to the `pcluster` and `chevron` CLI tools.

All steps below will assume the virtual environment is active.
- If using poetry, see [the docs](https://python-poetry.org/docs/basic-usage#activating-the-virtual-environment) for activation methods.

## Creating the VPC
To create the cluster, we first have to set up the
[Virtual Private Cloud](https://docs.aws.amazon.com/vpc/latest/userguide/what-is-amazon-vpc.html) network.

To do so, run:
```bash
pcluster configure -c temp-config.yml
```

This will take you through a configuration wizard.
Most of the prompts can be left at their defaults, because we will not be using `temp-config.yml`
to create the cluster.

Below are the important fields, and what to input for them.

```text
Allowed values for AWS Region ID:
    This must be the correct region, as it cannot be changed later.

Allowed values for EC2 Key Pair Name:
    This must be the key pair you created and imported locally. It will be used to login to the head node.

Allowed values for Scheduler:
    slurm

Automate VPC creation? (y/n) [n]:
    y

Allowed values for Network Configuration:
    Head node in a public subnet and compute fleet in a private subnet

Automate Subnet creation? (y/n) [y]:
    y
```

Once complete, the tool will initiate the creation of the private and public VPCs.
You can monitor the progress on [CloudFormation](https://console.aws.amazon.com/cloudformation/home).

## Creating the cluster configuration file

This repo provides a [configuration template](./config.template.yml) for a basic Slurm cluster.
See [here](https://docs.aws.amazon.com/parallelcluster/latest/ug/cluster-configuration-file-v3.html) for documentation on cluster configuration files.

The [chevron](https://github.com/noahmorrison/chevron) CLI tool can be used to populate
this template with the necessary fields from a [parameter file](./config-parameters.example.json).

First, make a copy of the config parameter example file:

```bash
cp config-parameters.example.json config-parameters.yml
```

Fill the parameter values in `config-parameters.json`.
Most of the parameters will be obtained from the `temp-config.yml` we have just created.
The table below details where to obtain the parameters.

<table>
<tr>
<th> Parameter Key </th> <th> Description </th> <th> Source </th>
</tr>

<!-- row -->
<tr>
<td>

`AWS_REGION`

</td>
<td> The AWS region the cluster will be deployed in. </td>
<td>

```yaml
# temp-config.yml
Region: <here>
```

</td>

<!-- row -->
<tr>
<td>

`SSH_KEY_PAIR`

</td>
<td> The AWS EC2 key pair that will be used to connect to the cluster head node </td>
<td>

```yaml
# temp-config.yml
HeadNode:
  Ssh:
    KeyName: <here>
```

</td>
</tr>

<!-- row -->
<tr>
<td>

`PRIVATE_SUBNET`

</td>
<td>

The private subnet created by the configure tool.

All compute nodes will be members of this subnet.

</td>
<td>

```yaml
# temp-config.yml
Scheduling:
  SlurmQueues:
    - Name: queue1
      Networking:
        SubnetIds:
          - <here>
```

</td>
</tr>

<!-- row -->
<tr>
<td>

`PUBLIC_SUBNET`

</td>
<td>

The public subnet created by the configure tool.

The head node will be a member of this subnet.

</td>
<td>

```yaml
# temp-config.yml
HeadNode:
  Networking:
    SubnetId: <here>
```

</td>
</tr>

<!-- row -->
<tr>
<td>

`CUSTOM_BOOT_ACTION_START`

</td>
<td>

The URI pointing to a script that will be run on the all nodes once they are booted but before they are configured.

See [here](https://docs.aws.amazon.com/parallelcluster/latest/ug/custom-bootstrap-actions-v3.html) for more info on custom bootstrap actions.

</td>
<td>

This corresponds to [this script](./on_node_start_ubuntu.sh),
but the script must be made available publicly - either via `http` or [`S3`](https://aws.amazon.com/s3/).

</td>
</tr>

<!-- row -->
<tr>
<td>

`CUSTOM_BOOT_ACTION_CONFIGURED`

</td>
<td>

The URI pointing to a script that will be run on the all nodes after they are booted and configured.

See [here](https://docs.aws.amazon.com/parallelcluster/latest/ug/custom-bootstrap-actions-v3.html) for more info on custom bootstrap actions.

</td>
<td>

This corresponds to [this script](./on_node_configured_ubuntu.sh),
but the script must be made available publicly - either via `http` or [`S3`](https://aws.amazon.com/s3/).

</td>
</tr>


<!-- row -->
<tr>
<td>

`SLURM_JWT_KEY`

</td>
<td>

The JSON Web Token secret key that Slurm will use to authenticate API requests.

**Note:** This is used as an argument to the custom boot script.

</td>
<td>

This can be generated. It should be a random sequence of 32 or more characters.

**Note:** Keep reference of this, as the UQLE API uses the JWT key to authenticate requests.

**Note:** The JWT key is all that is needed to deploy jobs to the Slurm cluster, and so must be kept safe if the REST API is exposed publicly (not recommended).

</td>
</tr>

</table>

Once all parameter values are filled, run the following.

```bash
chevron --data config-parameters.json config.template.yml > config.yml
```

The file `config.yml` will be generated. This file can now be used to create the cluster.

## Creating the cluster

Run the following to initiate creation of the Slurm cluster.

```bash
pcluster create-cluster --cluster-configuration ./config.yml --cluster-name <cluster-name>
```

The progress of the creation can be monitored from [CloudFormation](https://eu-west-2.console.aws.amazon.com/cloudformation/home).

## Connecting the cluster to the UQLE API
To complete the stack, a new EC2 instance must be created.
This will host the UQLE API service and the GitLab runner service.

The Gitlab runner service will need access to the shared EFS filesystem of the cluster, to extract artifacts.
The UQLE API service will need access the the Slurm REST API port on the Head Node of the cluster.

To achieve this, the following steps must be followed:
- Create an inbound rule on the cluster's Head Node Security Group (HNSG)
- Create the EC2 instance, attaching it to the HNSG and the EFS filesystem

See below for details on these steps.

### Modify Head Node Security Group
When the cluster is created by the `pcluster create-cluster` command,
2 security groups are created in the VPCs created by the `pcluster configure` command.
These security groups correspond to the head node, and the compute nodes.

By default, the HNSG allows all inbound traffic from the Compute Node Security group (CNSG).
We need to modify the HNSG to allow all inbound traffic from the HNSG.
This is because the EC2 instance will be added to the HNSG, and must be able to access the Slurm REST API port on the head node.

See the documentation on adding security group rules [here](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/working-with-security-groups.html#adding-security-group-rule)

The HNSG name has the format `pcluster-ubuntu-HeadNodeSecurityGroup-<id>`, where `<id>` is a random string of alphanumeric characters.

The screenshot below shows what the HNSG inbound rules should look like after modification.

![Security group modification page](./screenshots/security_group_modification.png "Security group modification page")

**Note:** The the security group ID being allowed access is the ID of this security group,
thus allowing all members of this security group to receive traffic from other members.

### Create the EC2 instance

The next step is to create the new EC2 instance. To do so, you can use the [EC2 launch wizard](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-launch-instance-wizard.html#liw-quickly-launch-instance).

See the guide given [here](https://docs.aws.amazon.com/efs/latest/ug/mount-fs-auto-mount-onreboot.html#mount-fs-auto-mount-on-creation) for a walkthrough on creating an EC2 instance which automounts an EFS filesystem.
You can skip the the security group configuration details in this guide.
For the UQLE API instance, the VPC, subnet and filesystem configuration deviates from this guide.
Those details are given below, with screenshots.

#### EC2 launch wizard settings

- Generally, any Linux-OS AMI should be appropriate.
- For the instance type, `t2.large` is a recommended minimum.
- Ensure you configure an accessible SSH key when creating the instance.

See the screenshot below for an example of the network settings that should be applied.

![EC2 wizard network settings](./screenshots/ec2_network_settings.png "EC2 wizard network settings")

Note that:
- The instance is within the same VPC as the cluster.
  - The VPC name will have the format `ParallelClusterVPC-<timestamp>`,
  where `<timestamp>` is the UTC timestamp of the VPC's creation.
- The instance is in the public subnet
- The instance is a member of the HNSG

This configuration will allow SSH access to the machine and, because of the HNSG modifications above,
the machine will have access to the Head Node of the Slurm Cluster.

See the screenshot below for an example of the filesystem settings that should be applied.

![EC2 wizard filesystem settings](./screenshots/ec2_filesystem_settings.png "EC2 wizard filesystem settings")

Note that:
- The filesystem ID corresponds to the EFS volume created by the `pcluster create-cluster` command
- *Automatically create and attach security groups* is unticked
  - The security groups already configured for the instance are sufficient to access the shared volume
- *Automatically mount shared file system by attaching required user data script* is ticked
  - This means no manual configuration is needed to make the Slurm cluster's shared volume accessible
- The mount point for the filesystem on the instance must be specified
  - This can be any directory, but should be noted for later configuration

All other configuration options can be left at defaults or modified as needed.

### Configure EC2 instance

To spin up the UQLE API service and the GitLab runner service, install docker and docker-compose on the instance and follow the documentation given in the [UQLE repo](https://github.com/Perpetual-Labs/uqle).

Details to note:
- The `Private IP DNS name` of the Head Node
  - This is used as the *Slurm URL* by the UQLE API
- The Slurm REST API port is `8082`
- The SLURM JWT key
  - This is used to spin up the UQLE API service
- The mount point of the shared volume
  - This mount point will be bind-mounted into the GitLab runner Docker container


## Debugging
### SSH Access

You can access the Head Node of the Slurm cluster using the SSH key it has been created with.
To do so, you will need to public IP address of the Head Node and have the private key pair saved locally.

Alternatively, you can use the `pcluster ssh` command, in which case you only need the key pair and the cluster name:

```shell
pcluster ssh --cluster-name pcluster-ubuntu -i ~/.ssh/key-pair.pem
```

## Useful References
[ParallelCluster v3 configuration file reference](https://docs.aws.amazon.com/parallelcluster/latest/ug/cluster-configuration-file-v3.html)

[Using the Slurm REST API to integrate with distributed architectures on AWS](https://aws.amazon.com/blogs/hpc/using-the-slurm-rest-api-to-integrate-with-distributed-architectures-on-aws/)

[Setting up and Using a Python Client Library for the Slurm REST API](https://github.com/aws-samples/aws-research-workshops/blob/b51852e083121f7edf92b65ff100f99e29643a11/notebooks/parallelcluster/pcluster-slurmrestclient.ipynb)

[AWS Workshop - Advanced Slurm on Parallelcluster](https://catalog.us-east-1.prod.workshops.aws/v2/workshops/d431e0b1-9f08-4d82-822e-ea56962b2a0b/en-US)

[Supported Slurm versions for ParallelCluster](https://docs.aws.amazon.com/parallelcluster/latest/ug/slurm-workload-manager-v3.html)
