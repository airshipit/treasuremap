# HostConfig-Operator

The hostconfig operator is used for performing Day2 configurations
on the kubernetes hosts. It is built on ansible-operator.

The operator uses HostConfig CR object to select the hosts.
The CR object also contains the required configuration details
that needs to be performed on the selected hosts. The host selection
is done by matching the labels given in the CR object
against the labels associated with the kubernetes hosts.

## Usage and deployment details

For more information on usage and deployment of the operator
on a stand alone kubernetes please refer below.

[Overview and Deployment details](https://opendev.org/airship/hostconfig-operator/src/branch/master/docs/Overview.md)

HostConfig Repo:
[hostconfig-operator](https://opendev.org/airship/hostconfig-operator)
