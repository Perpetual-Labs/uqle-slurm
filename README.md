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

Allowed values for Operating System:
    alinux2

Automate VPC creation? (y/n) [n]:
    y

Allowed values for Network Configuration:
    Head node in a public subnet and compute fleet in a private subnet

Automate Subnet creation? (y/n) [y]:
    y
```

Once complete, the tool will initiate the creation of the private and public VPCs.
You can monitor the progress on [CloudFormation](https://eu-west-2.console.aws.amazon.com/cloudformation/home).

## Create an EC2 instance within the public subnet
A separate EC2 instance is used to spin up the UQLE API service.
- Create the EC2 instance in the public VPC created in the steps above
- Follow the steps given in the UQLE Stack repository to spin up services
- Add a security group rule that allows the private subnet of the cluster access to the UQLE API port
- Note the private IP address of the EC2 instance

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

`CUSTOM_BOOT_ACTION_SCRIPT`

</td>
<td>

The URI pointing to a script that will be run on the all nodes once they are booted and configured.

</td>
<td>

This corresponds to [this script](./custom-boot-action.sh),
but the script must be made available publicly - either via `http` or [`S3`](https://aws.amazon.com/s3/).

</td>
</tr>

<!-- row -->
<tr>
<td>

`SLURM_VERSION`

</td>
<td>

The Slurm version that will be built and installed onto the cluster head node.

**Note:** This is used as an argument to the boot action script.

</td>
<td>

`21.08.8` - as of *05-2022*

**Note:** The nodes already have slurm installed, but is rebuilt and re-installed in a
custom action in order to enable the Slurm REST API. The cluster obtains Slurm binaries
from an nfs-share, so rebuilding Slurm on the head node will propogate to the cluster.

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


<!-- row -->
<tr>
<td>

`MACHINE_USER_TOKEN`

</td>
<td>

The [Personal Access Token](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/creating-a-personal-access-token) (PAT) for a GitHub [machine user](https://docs.github.com/en/developers/overview/managing-deploy-keys#machine-users)

**Note:** This is used as an argument to the custom boot script.

</td>
<td>

This can be created from any user that has read access to the both the UQLE stack and UQLE CLI repositories.

A user, [@uqle-machine-user](https://github.com/uqle-machine-user) has been created for this purpose.

</td>
</tr>

<!-- row -->
<tr>
<td>

`UQLE_CLI_TAG`

</td>
<td>

The release tag for the UQLE CLI tool to be installed into the gitlab runner on the head node.

**Note:** This is used as an argument to the custom boot script.

**Note:** The head node clones the UQLE stack repository, and uses it to build a gitlab runner. The `MACHINE_USER_TOKEN` is used in this process to clone the repository, and access the UQLE CLI binaries.

</td>
<td>

[github.com/Perpetual-Labs/uqle-cli/releases](https://github.com/Perpetual-Labs/uqle-cli/releases)


</td>
</tr>

<!-- row -->
<tr>
<td>

`UQLE_API_HOST`

</td>
<td>

The private IP of the EC2 instance created above for the UQLE API.

**Note:** This is used as an argument to the custom boot script.

**Note:** The host should include protocol and port
- *e.g.* `http://<private-ip>:2323`

</td>
<td>

You can view the private IP address of an EC2 instance from the [EC2 Dashboard](https://eu-west-2.console.aws.amazon.com/ec2/v2/home)


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

## Connecting cluster to UQLE API

- Add a security group rule to the head node instance that allows access from the public subnet to the slurmrestd port
<!-- TODO
Need to add info on adding to head node security group and hadding headnode group inbound rules
 -->
## Useful References
[ParallelCluster v3 configuration file reference](https://docs.aws.amazon.com/parallelcluster/latest/ug/cluster-configuration-file-v3.html)

[Using the Slurm REST API to integrate with distributed architectures on AWS](https://aws.amazon.com/blogs/hpc/using-the-slurm-rest-api-to-integrate-with-distributed-architectures-on-aws/)

[Setting up and Using a Python Client Library for the Slurm REST API](https://github.com/aws-samples/aws-research-workshops/blob/b51852e083121f7edf92b65ff100f99e29643a11/notebooks/parallelcluster/pcluster-slurmrestclient.ipynb)

[AWS Workshop - Advanced Slurm on Parallelcluster](https://catalog.us-east-1.prod.workshops.aws/v2/workshops/d431e0b1-9f08-4d82-822e-ea56962b2a0b/en-US)

[Supported Slurm versions for ParallelCluster](https://docs.aws.amazon.com/parallelcluster/latest/ug/slurm-workload-manager-v3.html)
