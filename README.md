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

Below are the important fields:

```text
Allowed values for AWS Region ID:
    This must be the correct region, as this cannot be changed later.

Allowed values for EC2 Key Pair Name:
    This must be the key pair you created and imported locally

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
You can monitor the progress of this process on [CloudFormation](https://eu-west-2.console.aws.amazon.com/cloudformation/home?region=eu-west-2).

## Creating cluster configuration

[chevron](https://github.com/noahmorrison/chevron) is used to fill fields
in the parallelcluster [configuration template](./config.template.yml) that cannot be automated.

First, make a copy of the config parameter example file:

```bash
cp config-parameters.example.json config-parameters.yml
```

Then fill the parameter keys in `config-parameters.yml` from the following sources:

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

`HEAD_NODE_CONFIGURED_SCRIPT`

</td>
<td>

The URI pointing to a script that will be run on the head node once it is booted and configured.

</td>
<td>

This corresponds to [this script](./pcluster-headnode-post-install.sh),
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

**Note:** This is used as an argument to the head node script.

</td>
<td>

`21.08.8` - as of *05-2022*

**Note:** The head node already has slurm installed, but is rebuilt and re-installed in
a custom action in order to enable the Slurm REST API. It is only rebuilt and re-installed
on the head node, so this may need to be changed if the Slurm version used by ParallelCluster
changes in future.

</td>
</tr>

<!-- row -->
<tr>
<td>

`SLURM_JWT_KEY`

</td>
<td>

The JSON Web Token secret key that Slurm will use to authenticate API requests.

**Note:** This is used as an argument to the head node script.

</td>
<td>

This can be generated. It should be a random sequence of 32 or more characters.

**Note:** Keep reference of this, as the UQLE API uses the JWT key to authenticate requests.

**Note:** The JWT key is all that is needed to deploy jobs to the Slurm cluster, and so must be kept safe if the REST API is exposed publicly (not recommended).

</td>
</tr>



</table>



2. Copy subnets, region and key pair fields into json file
3. Run pcluser create

TODO: add security group details for slurmrest port


## Updating the Cluster
## Useful References
[Using the Slurm REST API to integrate with distributed architectures on AWS](https://aws.amazon.com/blogs/hpc/using-the-slurm-rest-api-to-integrate-with-distributed-architectures-on-aws/)

[Setting up and Using a Python Client Library for the Slurm REST API](https://github.com/aws-samples/aws-research-workshops/blob/b51852e083121f7edf92b65ff100f99e29643a11/notebooks/parallelcluster/pcluster-slurmrestclient.ipynb)
- Includes examples outputting to S3

[AWS Workshop - Advanced Slurm on Parallelcluster](https://catalog.us-east-1.prod.workshops.aws/v2/workshops/d431e0b1-9f08-4d82-822e-ea56962b2a0b/en-US)
