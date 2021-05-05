# Phases for multi-tenant type

Phases defined in multi-tenant are available for use by sites
that inherit type mulit-tenant.

## Airshipctl phase command

For deploying calico network v3 policies, a phase named
`deliver-network-policy` is defined with its executor and configMap settings.

To deploy network policy using `airshipctl`, do

`airshipctl phase run deliver-network-policy` where `deliver-network-policy` is the phase name.

For deleting network policy, a phase named `delete-network-policy` is defined with its executor and configMap settings.

To delete network policy using `airshipctl`, do

`airshipctl phase run delete-network-policy` where `delete-network-policy` is the phase name.
