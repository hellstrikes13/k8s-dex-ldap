#!/bin/bash
rm -rf /etc/kubernetes/ssl
mkdir -p /etc/kubernetes/ssl
cd /etc/kubernetes
cat << EOF > ssl/req.cnf
[req]
req_extensions = v3_req
distinguished_name = req_distinguished_name

[req_distinguished_name]

[ v3_req ]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = dex.example.org
DNS.2 = login.k8s.example.org
DNS.3 = dex
DNS.4 = dex.auth.svc.cluster.local
DNS.5 = loginapp.auth.svc.cluster.local
DNS.6 = loginapp
IP.1 = 10.96.0.1
IP.2 = 10.0.2.15

EOF

openssl genrsa -out ssl/ca-key.pem 2048
openssl req -x509 -new -nodes -key ssl/ca-key.pem -days 1000 -out ssl/ca.pem -subj "/CN=kube-ca"

openssl genrsa -out ssl/key.pem 2048
openssl req -new -key ssl/key.pem -out ssl/csr.pem -subj "/CN=kube-ca" -config ssl/req.cnf
openssl x509 -req -in ssl/csr.pem -CA ssl/ca.pem -CAkey ssl/ca-key.pem -CAcreateserial -out ssl/cert.pem -days 1000 -extensions v3_req -extfile ssl/req.cnf
