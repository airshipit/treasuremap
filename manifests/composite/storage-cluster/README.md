# Rook Ceph CephCluster

Kubernetes manifests for deploying a Rook CephCluster Custom Resource.

## Update Manifests

To update the upstream manifests in this function:

1. Update the git references in `Kptfile`

2. Run `kpt pkg sync .` from this directory.

3. Update any `Rook` container image references defined in version catalogs.

4. If you plan on committing your changes restore the .gitignore file(s)

```
# git restore upstream/.gitignore
```
