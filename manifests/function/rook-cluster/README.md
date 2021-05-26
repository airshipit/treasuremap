In-place edits to the local copies of upstream Rook Custom Resource
examples are not recommended. The upstream examples can be considered
an immutable starting point.

Changes to the upstream examples should be made via Kustomize.

Rook Custom Resource Examples:

Upstream: https://github.com/rook/rook/blob/master/cluster/examples/kubernetes/ceph/filesystem.yaml
Local: cephfs/base/filesystem.yaml
Tag: v1.6.3

Upstream: https://github.com/rook/rook/blob/master/cluster/examples/kubernetes/ceph/dashboard-external-http.yaml
Local: dashboard/base/dashboard-external-http.yaml
Tag: v1.6.3

Upstream: https://github.com/rook/rook/blob/master/cluster/examples/kubernetes/ceph/pool.yaml
Local: pools/base/pool.yaml
Tag: v1.6.3

Upstream: https://github.com/rook/rook/blob/master/cluster/examples/kubernetes/ceph/csi/rbd/storageclass.yaml
Local: storageclasses/block/storageclass.yaml
Tag: v1.6.3

Upstream: https://github.com/rook/rook/blob/master/cluster/examples/kubernetes/ceph/csi/cephfs/storageclass.yaml
Local: storageclasses/file/storageclass.yaml
Tag: v1.6.3

Kustomize Doc:

https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization
