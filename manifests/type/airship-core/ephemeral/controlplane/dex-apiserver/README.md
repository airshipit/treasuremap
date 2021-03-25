# DEX-APIServer kustomizations

The "dex-apiserver" folder provides the manifests and patches to configure the API server with
"oidc" flags.

In order to ensure synchronization with the "dex-aio" service, you MUST ensure that values
assigned to the API server "oidc" flags are the same used for the "dex-aio" service.

TODO: a shared catalogue shall provide the values shared between "dex-aio" service and
the cluster's API server "oidc" flags.