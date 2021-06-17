# DEX-AIO Workload Service

The "*kustomization*" of dex-aio service is achieved through replacement transformer and patches.
The rationale for supporting two different kustomization approaches is values for Dex service are shared with its corresponding API server.
The replacement transformer/catalogue avoids duplication of variables/values avoiding configuration errors (DRY: Don't Repeat Yourself principle).
The LDAP values are only used for the LDAP backend so supporting through patchesStrategyMerge avoids "complexity", e.i., the need to support a catalog + replacement rules.

## Dex Dependent Variables/Values
Dex dependent values are collected in a catalogue located at *manifests/function/treasuremap-base-catalogues/utility.yaml*.
Some of these values are common to the Dex service and API Server/OIDC flags (DRY principle).

Dex values are substituted using replacement transformer and the replacement rules for the Dex service can be found in *manifests/function/dex-aio/replacements*.

> NOTE: The replacement transformer is invoked in *treasuremap/manifests/type/airship-core/target/workload/replacements/kustomization.yaml*.

## LDAP Dependent Variables/Values
The LDAP dependent values are kustomized through the *patchesStrategyMerge* and the values for the LDAP backend can be found in *./dex-aio-helm-patch.yaml*.