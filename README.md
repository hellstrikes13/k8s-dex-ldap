# Kubernetes - LDAP authentication with Dex Updated as on 2021 30th JAN

* [Docs](#docs)
* [Requirements](#requirements)
* [Login application](#login-application)
* [Dex](#dex)
  * [CRD](#crd)
  * [Deployment](#deployment)
* [Test](#test)

## Docs

This deployment follows Dex by CoreOS & Kubernetes Documentations:

* [Kubernetes OIDC Doc](https://kubernetes.io/docs/admin/authentication/#option-1---oidc-authenticator)
* [Dex by CoreOS](https://github.com/coreos/dex)
* [Login App](https://github.com/Flav35/loginapp)

## Requirements

I have used Virtualbox on Ubuntu OS runing following :

- k8s 1 node cluster bootstrapped thru  kubeadm (kube-api-server running as POD) 
- dex (running as pod)
- loginapp (running as POD)
- ldap server(running as standalone application not under POD)

#### SPECS:
- OS: Ubuntu 20 (CPU: 2 cores RAM:4G disk: 40G)
- go version go1.15.7 linux/amd64
- Docker Community Version: 20.10.2
- k8s: Server Version: "v1.20.2"

### To create simple LDAP server:

```shell
cat <<EOF | debconf-set-selections
slapd slapd/password1 password adminpassword
slapd slapd/password2 password adminpassword
slapd slapd/domain string mycompany.com
slapd shared/organization string mycompany.com
EOF

apt-get update
apt-get install -y slapd ldap-utils

cat ouusers.ldif
dn:  ou=users,dc=mycompany,dc=com
objectClass: organizationalUnit
ou: users

cat ougroups.ldif
dn:  ou=groups,dc=mycompany,dc=com
objectClass: organizationalUnit
ou: groups

cat devops_user.ldif
####### hero
dn: uid=hero,ou=users,dc=mycompany,dc=com
objectClass: top
objectClass: inetOrgPerson
gn: Hero
sn: blah
cn: hero
uid: heblah
mail: heblah@mycompany.com
userPassword: heman123
ou: users


######### joker
dn: uid=joker,ou=users,dc=mycompany,dc=com
objectClass: top
objectClass: inetOrgPerson
gn: Joker
sn: blha
cn: joker
uid: jobblha
mail: joblha@mycompany.com
userPassword: funny123
ou: users

cat dev_users.ldif
####### brahma
dn: uid=brahma,ou=users,dc=mycompany,dc=com
objectClass: top
objectClass: inetOrgPerson
gn: Brahma
sn: bhagwan
cn: bhrahma
uid: brawan
mail: brawan@mycompany.com
userPassword: test1234
ou: users

######### mahesh
dn: uid=mahes,ou=users,dc=mycompany,dc=com
objectClass: top
objectClass: inetOrgPerson
gn: Mahesh
sn: bhagwan
cn: mahesh
uid: mahwan
mail: mahwan@mycompany.com
userPassword: test7890
ou: users


cat devops_group.ldif
dn: cn=devops,ou=groups,dc=mycompany,dc=com
objectClass: top
objectClass: groupOfNames
cn: devops
member: uid=heblah,ou=users,dc=mycompany,dc=com
member: uid=joblha,ou=users,dc=mycompany,dc=com
ou: groups

cat dev_group.ldif
dn: cn=dev,ou=groups,dc=mycompany,dc=com
objectClass: top
objectClass: groupOfNames
cn: dev
member: uid=brawan,ou=users,dc=mycompany,dc=com
member: uid=mahwan,ou=users,dc=mycompany,dc=com
ou: groups

for i in ouusers.ldif ougroups.ldif devops_user.ldif dev_user.ldif  devops_group.ldif dev_group.ldif
do
 ldapadd -H ldap://127.0.0.1  -x -D cn=admin,dc=mycompany,dc=com -w adminpassword -f $i
done

ldapsearch -LLL -H ldap://127.0.0.1   -x -D cn=admin,dc=mycompany,dc=com -w adminpassword   -b dc=mycompany,dc=com cn=devops
ldapsearch -LLL -H ldap://127.0.0.1   -x -D cn=admin,dc=mycompany,dc=com -w adminpassword   -b dc=mycompany,dc=com uid=mahwan
```

* DNS entries: (Since this configuration uses NodePort, these can be CNAMEs to your kubernetes nodes)
  for DNS entries pointing to loginapp,dex,ldap 
  edit coredns configmap append following entry

```shell
 kubectl edit cm coredns -n kube-system
 hosts custom.hosts example.org {
      10.0.2.15 ldap.k8s.example.org dex.example.org login.k8s.example.org
      fallthrough
    }
```
  note:10.0.2.15 is the IP of my machine (NAT IP)
  ```shell
  vim /etc/host
   10.0.2.15	control-plane.minikube.internal  ldap.k8s.example.org dex.example.org login.k8s.example.org
  ```
  * **dex.example.org** --> Dex OIDC provider
  * **login.k8s.example.org** --> Custom Login Application
  * **ldap.k8s.example.org --> Ldap server without TLS


* once Kubernetes cluster is up append following entries /etc/kubernetes/manifest/kube-apiserver.yaml
  * RBAC enabled
  * OIDC authentication enabled. API server configuration:
    * **--oidc-issuer-url=https://dex.example.org:32000 ( External Dex endpoint)
    * **--oidc-client-id=loginapp (ID for our Login Application)
    * **--oidc-ca-file=/etc/kubernetes/ssl/ca.pem (CA file generated using gencert.sh this file is needed so that k8 cluster can trust dex CA )
    * **--oidc-username-claim=name ( Map to **nameAttr** Dex configuration. This will be used by Kubernetes RBAC to authorize users based on their name.)
    * **oidc-groups-claim=groups(This will be used by Kubernetes RBAC to authorize users based on their groups)

make sure you have volume mounts for dex certs on k8s cluster

Below is the Snippet from /etc/kubernetes/manifest/kube-api-server.yaml
```shell
spec:
  containers:
  - command:
    - --oidc-issuer-url=https://dex.example.org:32000
    - --oidc-client-id=loginapp
    - --oidc-ca-file=/etc/kubernetes/ssl/ca.pem
    - --oidc-username-claim=name
    - --oidc-groups-claim=groups
  volumes:
  volumeMounts:
  - mountPath: /etc/kubernetes/ssl
      name: dex-certs
      readonly: true
  - hostPath:
      path: /etc/kubernetes/ssl
      type: DirectoryOrCreate
    name: dex-certs
 ```    
after above changes are done kubeapi-server will restart for a minute check thru command
kubectl version

* An available LDAP server

## Login application

* Create the auth namespace:

```shell
kubectl create ns auth
```

* Create required SSL certs and secrets (make sure to update alt_names to match your domain)

```shell
#this shall generate self signed certs under /etc/kubernetes/ssl you may edit the script as per your needs)
openssl rand -out /root/.rnd -hex 256
./gencert.sh
kubectl create secret tls login.k8s.example.org.tls --cert=/etc/kubernetes/ssl/cert.pem --key=/etc/kubernetes/ssl/key.pem -n auth
kubectl create secret tls dex.example.org.tls --cert=/etc/kubernetes/ssl/cert.pem --key=/etc/kubernetes/ssl/key.pem -n auth
```

* Create resources:

```shell
# CA ( ca.pem generated by gencert.sh) configmap
kubectl create -f ca-cm.yml
# Login App configuration
kubectl create -f loginapp-cm.yml
# Login App service
kubectl create -f loginapp-ing-svc.yml
# Login App Deployment
kubectl create -f loginapp-deploy.yml
```

loginapp pod status will be completed  but wont be able to serve anything
because Dex is not deployed.

## Dex

### CRD

We will use Kubernetes Custom Resource Definitions (https://kubernetes.io/docs/concepts/api-extension/custom-resources/) as Dex storage backend.

```shell
kubectl create -f dex-crd.yml
```

### Deployment

* Create Dex resources:

```shell
# Dex configuration
kubectl create -f dex-cm.yml
# Dex service
kubectl create -f dex-ing-svc.yml
# Dex deployment
kubectl create -f dex-deploy.yml
```

try https://login.k8s.example.org:32002, login and retrieve k8s configuration.
decode your token thru https://jwt.io

* Create RBAC resource

```shell
kubectl create -f rbac.yml
```

Now copy paste the  Full kubeconfig file from loginapp Web UI to your ~/.kube/config on shell account

```shell
root@sudik8s:~/k8s-ldap# kubectl get po -n auth
NAME                        READY   STATUS    RESTARTS   AGE
dex-c47dfcb45-6f8c2         1/1     Running   0          22m
loginapp-6749dd76f4-z2vwl   1/1     Running   0          22m

kubectl logs -f <above PODNAME>
```


