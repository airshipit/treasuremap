# DEX-APIServer kustomizations

The "dex-apiserver" folder provides the manifests and patches to configure the API server with
"oidc" flags and CA certificate (Secret). Refer to the JSON patch file *oidc-apiserver-flags.json*.
This patch file adds OIDC flags configuration to the API server in the KubeadmControlPlane CR,
which is used to create the Target cluster's ControlPlane node and deploy the API server during
the execution of ***airshipctl phase run controlplane-ephemeral*** command.

>IMPORTANT: The JSON patch is tailored for baremetal provider. If deploying target cluster on a
>different provider (e.g., Azure, GCP, Openstack), you will need to update this patch, accordingly.

In order to ensure synchronization with the "dex-aio" service, the CA certificate (Secret)
in the Ephemeral cluster SHALL be copied to the Target cluster. This is achieved by adding the label
**clusterctl.cluster.x-k8s.io/move: "true"** to the CA Secret. This label idenfies this Secret as
candidate to the CAPI move command executed by ***airshipctl phase run clusterctl-move*** command.

Once this CA Secret has been moved to the Target cluster, it will be used during **dex-aio** deployment
to sign Certificates to be used by Dex.

>NOTES on **oidc-apiserver-flags.json**:
* The (Dex) FQDN for the attribute **oidc-issuer-url** will have to be added to the list under **certSANs**
* The patches for **"/spec/kubeadmConfigSpec/preKubeadmCommands/-"** are needed if your (Dex) FQDN cannot be resolved by the DNS used by the controlplane node.
* The **oidc-issuer-url** FQDN and port number MUST match **dex-aio** HelmRelease values for **values.params.endpoints.hostname** and **values.params.endpoints.port.https**. Example below:

Snippet of **oidc-apiserver-flags.json**
```json
  {
    "op": "add",
    "path": "/spec/kubeadmConfigSpec/clusterConfiguration/apiServer",
    "value": {
      "extraArgs":
      {
        "oidc-issuer-url": "https://dex.function.local:32556/dex",
      },
```

Snippet of **treasuremap/manifests/function/dex-aio/dex-helmrelease.yaml**
```yaml
  values:
    params:
      endpoints:
        hostname: dex.function.local
        port:
          https: 32556
```

Also, in case your **dex-aio** FQDN (e.g., **dex.function.local**) cannot be resolved by the DNS configured
in the control plane node, your JSON patch will also have to include this FQDN to the nodes **/etc/hosts**
so that the API server can reach **dex-aio** microservice.

Snippet of **oidc-apiserver-flags.json**
```json
  {
    "op": "add",
    "path": "/spec/kubeadmConfigSpec/preKubeadmCommands/-",
    "value": "echo '10.23.25.102 dex.function.local' | tee -a /etc/hosts"
  }
```

>NOTES on **dex-ca-cert-secret.yaml**:
* This Secret contains a Certificate Authority (CA) certificate manually generated.
* The CA certificate was not signed by a known authority

>TODO(s):
* CA certificate shall be auto generated
* The CA certificate shall be signed by a known authority
* The generated CA certificate shall be secured, e.g., encrypted using SOPS