# Support Infrastructure Provider (SIP)

The Support Infrastructure Provider (SIP) provisions tenant Kubernetes clusters
using BaremetalHost (BMH) objects and deploys supporting infrastructure to
access sub-clusters.

View the source code for SIP on [OpenDev][repo].

[repo]: https://opendev.org/airship/sip

## Update Manifests

To update the upstream manifests in this function:

1. Update the git references in `Kptfile`.
2. Run `kpt pkg sync .` from this directory.
3. Update any `sip` container image references defined in version catalogs.
