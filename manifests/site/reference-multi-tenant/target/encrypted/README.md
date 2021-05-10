# Secrets generator/encrypter/decrypter

This directory contains an utility that helps generate, encrypt and decrypt
secrects. These secrects can be used anywhere in manifests.

For example we can use PGP key from SOPS example.
To get the key we need to run:
`curl -fsSL -o key.asc https://raw.githubusercontent.com/mozilla/sops/master/pgp/sops_functional_tests_key.asc`

and import this key as environment variable:
`export SOPS_IMPORT_PGP="$(cat key.asc)" && export SOPS_PGP_FP="FBC7B9E2A4F9289AC0C1D4843D16CEE4A27381B4"`

## Generator

To generate secrets we use [template](secret-template.yaml) that will be passed
to kustomize as [generators](kustomization.yaml) during `airshipctl phase run secret-generate`
execution.

## Encrypter

To encrypt the secrets that have been generated we use generic container executor.
To start the secrets generate phase we need to execute following phase:
`airshipctl phase run secret-generate`
The executor run SOPS container and pass the pre-generated secrets to this container.
This container encrypt the secrets and write it to directory specified in `kustomizeSinkOutputDir`(results/generated).

## Decrypter

To decrypt previously encrypted secrets we use [decrypt-secrets.yaml](results/decrypt-secrets.yaml).
It will run the decrypt sops function when we run
`KUSTOMIZE_PLUGIN_HOME=$(pwd)/manifests SOPS_IMPORT_PGP=$(cat key.asc) kustomize build --enable_alpha_plugins
manifests/site/test-site/target/catalogues/`
