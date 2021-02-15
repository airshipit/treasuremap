# Failsafe rules in calico

It is easy to inadvertently cut all host connectivity because of
non-existent or misconfigured network policy. To avoid this,
Calico provides failsafe rules with default/configurable ports
that are open on all host endpoints.

The manifest in this directory is planned to disable FailsafeInboundHostPorts
and FailsafeOutboundHostPorts by setting it none. This could be overriden in
the respective site manifests.


For more information on failsafe rules please refer below.

[Host Protection in Calico](https://docs.projectcalico.org/security/protect-hosts)

