# DEX-AIO function

The DEX-AIO function implements the Dex Authentication service.
It contains the HelmRelease manifest for **dex-aio**, which contains
the LDAP connector customization as well as certificates to be used.

The certificate (Secret) used by **dex-aio** will be generated by the
cert-manager, which will be signed by CA that is generated in
the Ephemeral cluster and copied to the Target cluster during the
***airshipctl phase run clusterctl-move*** operation.

Before you can deploy this helm release, you will need to update the following:

```yaml
      ldap:
        bind_password: "your LDAP bind password"
        config:
          host: "your LDAP FQDN"
          bind_dn: "your LDAP bind username"
```

Also, in the same helm release you will need to update the search criteria for
the user and group based on your LDAP schema. See the attributes under
**spec.values.ldap** to update below:

```yaml
      user_search:
        base_dn: dc=testservices,dc=test,dc=com
        filter: "(objectClass=person)"
        username: cn
        idAttr: cn
        emailAttr: name
        nameAttr: name
      group_search:
        base_dn: ou=groups,dc=testservices,dc=test,dc=com
        filter: "(objectClass=group)"
        userMatchers:
          userAttr: name
          groupAttr: member
        nameAttr: name
```