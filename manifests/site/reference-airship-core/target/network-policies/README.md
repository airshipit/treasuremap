# Network Policy  in calico

Restricting traffic between hosts and the outside world can be achieved
using the following Calico features:

* HostEndpoint resource
* GlobalNetworkPolicy
* FelixConfiguration resource with parameters:
  -FailsafeInboundHostPorts
  -FailsafeOutboundHostPorts
Generally a cluster-wide policy is applied to every host.

This site based manifest is designed to override the default global
FelixConfiguration based in function directory.

For more information on failsafe rules please refer below.

[Host Protection in Calico](https://docs.projectcalico.org/security/protect-hosts)

