# DEX-AIO function

The DEX-AIO function implements the Dex Authentication service.
It contains the HelmRelease manifest for dex-aio, the dex-aio secrets
for the key and certificates, and the cluster issuer for dex-aio.

TODO: The values are "hard-coded" for this version that can be made more
flexible later with Kustomization transformers. A shared catalogue
between "dex-aio" function and "type/multi-tenant/ephemeral/controlplane/dex-apiserver"
shall be provided to ensure synchronization between them.