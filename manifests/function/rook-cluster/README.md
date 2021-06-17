# Rook Ceph Custom Resources

Kubernetes manifests for deploying select Rook Ceph Custom Resources.

## Update Manifests

To update the upstream manifests in this function:

1. Update the git references in `Kptfile`

2. Run `kpt pkg sync .` from this directory.

3. Update any `Rook` container image references defined in version catalogs.

4. If you plan on committing your changes restore the .gitignore file(s)

```
# git restore cephfs/base/upstream/.gitignore
# git restore dashboard/base/upstream/.gitignore
# git restore pools/base/upstream/.gitignore
# git restore storageclasses/block/upstream/.gitignore
# git restore storageclasses/file/upstream/.gitignore
```
