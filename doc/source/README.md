## Prerequisites: Deploy Airship in a Bottle(AIAB)

To get started, run the following in a fresh Ubuntu 16.04 VM (minimum 4vCPU/20GB RAM/32GB disk).
This will deploy Airship and Openstack Helm (OSH).

1. Add the below to /etc/sudoers

```
root    ALL=(ALL) NOPASSWD: ALL
ubuntu  ALL=(ALL) NOPASSWD: ALL
```

2. Install the latest versions of Git, CA Certs & bundle & Make if necessary

```
set -xe \
sudo apt-get update \
sudo apt-get install --no-install-recommends -y \
ca-certificates \
git \
make \
jq \
nmap \
curl \
uuid-runtime
```

## Deploy Airship in a Bottle(AIAB)

3. Deploy airShip in a Bottle(AIAB) for all utility containers

```
sudo -i \
mkdir -p root/deploy && cd "$_" \
git clone https://opendev.org/airship/treasuremap

If this ps is not merged please checkout this ps https://review.opendev.org/#/c/680482

To deploy airship-in-a-bottle with porthole utility containers included, please change the value of `data.armada.manifests` from `full-site-aiab` to `full-site-utilities` in the deployment-configuration.yaml file.

https://opendev.org/airship/treasuremap/src/branch/master/site/aiab/deployment/deployment-configuration.yaml#L38

cd /root/deploy/treasuremap/tools/deployment/aiab
./airship-in-a-bottle.sh
```
