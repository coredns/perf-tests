# Kubernetes Scale Environment Deployment
 
The k8s-scale.sh script will generate and deploy the scale testing environment.  It does the following...

* Replaces kube-dns with coredns as the kube-dns service
* Deploys a scale set of “dummy” pods/services/endpoints
* Configures a prometheus service to gather coredns performance metrics

``` 
usage: ./scale.sh -n <namespace> [-d <domain>] [-i <ip-address>] [-u <cidr>] [-p <n>] [-s <n>] [-h <n>] [-q <n>] [FILENAME OPTIONS]

   -n : Namespace to hold the “dummy” objects (default: scale) NOTE: Any existing objects in the namespace will be deleted.
   -d : The domain (default: cluster.local)

   -i : Starting cluster IP address for services. Required if services deployed > 0.
   -u : The cluster ip subnet cidr for which CoreDNS will serve PTR requests.

   -p : Number of pods (non-endpoint pods)
   -s : Number of services
   -h : Number of headless services (without Cluster IP)
   -e : Number of endpoints per service (default: 2)

   FILENAME OPTIONS

   -y : Filename for the kubernetes yaml object definition file (default: scale-objs.yaml)
   -c : Filename for the coredns yaml definition file (default: coredns.yaml)
   -m : Filename for the prometheus yaml definition file (default: prometheus.yaml)

   -a : Filename for the pod/service A record names list (default: scale-a.lst)
   -r : Filename for the service PTR record names (default: scale-ptr.lst)
   -v : Filename for the service SRV record names (default: scale-srv.lst)

```

For example, the following command will create 50 pods, 50 services with 2 endpoints each, in the “scale” namespace.  25 of the services will be headless, the other 25 will have cluster IPs 10.96.0.200-10.96.0.224.

``` 
$ ./scale.sh -i 10.96.0.200 -u 10.96.0.0/24 -p 50 -s 25 -h 25 -e 2
```
 
Upon completion, the tool returns a summary of the objects deployed, a list of DNS record name file names, which contain all valid A, PTR, and SRV records, and ip address/url for coredns and prometheus services.  For example:

``` 
Object Deployment Summary
  Pods (excluding endpoints): 20
  Services: 10
  Headless Services: 10
  Endpoints Per Service: 2
  Total Pods (including endpoints): 60
  Total Endpoints: 40
  Total Services: 20

Object definition file: scale-objs.yaml
CoreDNS deployment file: coredns.yaml
Prometheus deployment file: prometheus.yaml

A record list file: scale-a.lst
PTR record list file: scale-ptr.lst
SRV record list file: scale-srv.lst

DNS IP: 10.96.0.10
Local Prometheus URL: http://10.108.165.249:9090
```
