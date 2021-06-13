#!/bin/bash
set -xe
set -o pipefail

echo "Target directory location = $1"
# check if certificates are already present
# TBD should validity of existing certs be checked.
if  [ -f $1/ca-cert.pem ] && [ -f $1/server-cert.pem ] && [ -f $1/server-key.pem ]
then
       echo "ca-cert.pem, server-cert.pem and server-key.pem already present"
       exit 0
else
# create a temp dir
TMP=$(mktemp -d)
cd ${TMP}
# create ca certificate
echo ' cn = airshipit.org
  ca
  cert_signing_key' > ca-template.info

(umask 277 && certtool --generate-privkey > ca-key.pem)

certtool --generate-self-signed \
	 --template ca-template.info \
	 --load-privkey ca-key.pem \
	 --outfile ca-cert.pem

rm ca-template.info

echo ' organization = airshipit.org
 cn = server
  tls_www_server
   encryption_key
    signing_key' > server-template.info

(umask 277 && certtool --generate-privkey > server-key.pem)

# create server certificate
certtool --generate-certificate \
         --template server-template.info \
         --load-privkey server-key.pem \
         --load-ca-certificate ca-cert.pem \
         --load-ca-privkey ca-key.pem \
         --outfile server-cert.pem

rm server-template.info

# copy the required certs in the target location
echo "Copy the required certs to target location : $1"
cp *.pem $1

#echo ' country = Country
# state = State
# locality = City
# organization = Name of your organization
# cn = Client Host Name
# tls_www_client
# encryption_key
# signing_key' > client-template.info

#(umask 277 && certtool --generate-privkey > client-key.pem)

#certtool --generate-certificate
#          --template client-template.info
#	  --load-privkey client-key.pem
# 	  --load-ca-certificate ca-cert.pem
#	  --load-ca-privkey ca_key.pem
#	  --outfile client-cert.pem
fi
exit 0
