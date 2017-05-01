#!/bin/bash

show_help () {
cat << EOF

usage: $0 [-o] [-n <namespace>] [-d <domain>] [-i <ip-address>] [-u <cidr>] [-p <n>] [-s <n>] [-h <n>] [-e <n>] [FILENAME OPTIONS] 

   -o : Only provision test scale objects. Dont provision prometheus, and leave dns as-is.
   -n : Namespace to hold all objects (default: scale)
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

EOF
exit 0
}

[ $# -eq 0 ] && show_help

# yaml templates
#
coredns_yaml_template="coredns.sed.yaml"
prometheus_yaml_template="prometheus.sed.yaml"

# Defaults
#
configure_coredns=1
configure_prometheus=1
namespace="scale"
domain="cluster.local"

start_ip_a='10.0.8.1'
service_cidr='10.0.8.0/24'

pods=0
services=0
headless_services=0
pods_per_service=2

yaml="scale-objs.yaml"
prometheus_yaml="prometheus.yaml"
coredns_yaml="coredns.yaml"

names="scale-a.lst"
ptrs="scale-ptr.lst"
srvs="scale-srv.lst"

# Get Options
#
OPTIND=1 # Reset in case getopts has been used previously in the shell.
while getopts "?on:d:i:u:p:s:h:e:y:c:m:a:r:v:" opt; do
    case "$opt" in
    \?)
        show_help
        ;;
    o)  configure_coredns=0
        configure_prometheus=0
        ;;
    n)  namespace=$OPTARG
        ;;
    i)  start_ip_a=$OPTARG
        ;;
    u)  service_cidr=$OPTARG
        ;;
    p)  pods=$OPTARG
        ;;
    s)  services=$OPTARG
        ;;
    h)  headless_services=$OPTARG
        ;;
    e)  pods_per_service=$OPTARG
        ;;
    d)  domain=$OPTARG
        ;;
    y)  yaml=$OPTARG
        ;;
    c)  coredns_yaml=$OPTARG
        ;;
    m)  prometheus_yaml=$OPTARG
        ;;
    a)  names=$OPTARG
        ;;
    r)  ptrs=$OPTARG
        ;;
    v)  srvs=$OPTARG
        ;;
    esac
done

shift $((OPTIND-1))

[ "$1" = "--" ] && shift

# Functions
#

show_summary () {
  echo "Object Deployment Summary"
  echo "  Pods (excluding endpoints): $pods"
  echo "  Services: $services"
  echo "  Headless Services: $headless_services"
  echo "  Endpoints Per Service: $pods_per_service"
  echo "  Total Pods (including endpoints): $((pods+services*pods_per_service+headless_services*pods_per_service))"
  echo "  Total Endpoints: $((services*pods_per_service+headless_services*pods_per_service))"
  echo "  Total Services: $((services+headless_services))"
  echo
  echo Object definition file: $yaml
  echo CoreDNS deployment file: $coredns_yaml
  echo Prometheus deployment file: $prometheus_yaml
  echo
  echo A record list file: $names
  echo PTR record list file: $ptrs
  echo SRV record list file: $srvs
  echo
  echo DNS IP: $dns_ip
  echo Local Prometheus URL: http://${prometheus_ip}:9090
}

atoi () {
  #Returns the integer representation of an IP arg, passed in ascii dotted-decimal notation (x.x.x.x)
  IP=$1; IPNUM=0
  for (( i=0 ; i<4 ; ++i )); do
    ((IPNUM+=${IP%%.*}*$((256**$((3-${i}))))))
    IP=${IP#*.}
  done
  echo $IPNUM 
} 

itoa () {
#returns the dotted-decimal ascii form of an IP arg passed in integer format
  echo -n $(($(($(($((${1}/256))/256))/256))%256)).
  echo -n $(($(($((${1}/256))/256))%256)).
  echo -n $(($((${1}/256))%256)).
  echo $((${1}%256)) 
}


next_ip () {
  echo $(itoa $(($(atoi $1)+1)))
}

pod_yaml () {
  podname=$1

  cat << EOF
apiVersion: v1
kind: Pod
metadata:
  name: $podname
  namespace: $namespace
  labels:
    app: app-none
spec:
  containers:
  - name: container-$podname
    image: gcr.io/google_containers/pause-amd64:3.0
    ports:
    - containerPort: 1234
      name: c-port
      protocol: UDP
---
EOF
}

service_pod_yaml () {
  servicename=$1
  podname=$2

  cat << EOF
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: $podname
  namespace: $namespace
spec:
  replicas: $pods_per_service
  template:
    metadata:
      labels:
        app: app-$servicename
    spec:
      containers:
      - name: container-$podname
        image: gcr.io/google_containers/pause-amd64:3.0
        ports:
        - containerPort: 9999
          name: scale-port
          protocol: TCP
---
EOF
}

service_yaml () {
  servicename=$1
  clusterip=$2

  cat << EOF
apiVersion: v1
kind: Service
metadata:
  name: $servicename
  namespace: $namespace
spec:
  selector:
    app: app-$servicename
  clusterIP: $clusterip
  ports:
  - name: scale-port
    port: 9999
    protocol: TCP
---
EOF

  service_pod_yaml $servicename ${servicename}-pod
}

namespace_yaml () {
  ns=$1
  cat << EOF
apiVersion: v1
kind: Namespace
metadata:
  name: $ns
---
EOF
}

count_running_pods () {
  kubectl -n $namespace get pods | grep Running | wc -l
}

count_all_pods () {
  kubectl -n $namespace get pods 2> /dev/null | tail -n +2 | wc -l
}

count_all_services () {
  kubectl -n $namespace get services 2> /dev/null | tail -n +2 | wc -l
}

count_all_deployments () {
  kubectl -n $namespace get deployments 2> /dev/null | tail -n +2 | wc -l
}

wait_indicator () {
 spin='-\|/'
 for i in {0..3}; do
  i=$(( (i+1) %4 ))
  printf "\r   $1 ${spin:$i:1} \r"
  sleep .25
 done
}

# Main
#

# Clear out files
#
echo -n > $yaml
echo -n > $names
echo -n > $ptrs
echo -n > $srvs


# Get the currently deployed dns service ip
#
dns_ip=$(kubectl get service --namespace kube-system kube-dns -o jsonpath="{.spec.clusterIP}")

if [ $configure_coredns -eq 1 ]; then
  # Replace kube-dns with coredns
  #
  echo Adding coredns deployment for kube-dns service in Kubernetes
  sed -e s/CLUSTER_DNS_IP/$dns_ip/g -e s/CLUSTER_DOMAIN/$domain/g -e s?SERVICE_CIDR?$service_cidr?g $coredns_yaml_template > $coredns_yaml
  #kubectl delete --namespace=kube-system deployment kube-dns &> /dev/null
  #kubectl -n kube-system delete service kube-dns &> /dev/null
  kubectl apply -f $coredns_yaml 
fi

if [ $configure_prometheus -eq 1 ]; then
  # Add prometheus service
  #
  echo Deploying Prometheus to Kubernetes
  sed -e s/CLUSTER_DNS_IP/$dns_ip/g $prometheus_yaml_template > $prometheus_yaml
  kubectl delete service prometheus &> /dev/null
  kubectl apply -f $prometheus_yaml 
fi

# Generate scale object defintions and name lists for cluster ips
#
echo Generating object definitions and record lists

# Namespace
namespace_yaml $namespace >> $yaml

# Services with Cluster IPs (yaml + a/ptr/srv lists)
ip=$start_ip_a
for ((svcnum=1; svcnum<=$services; svcnum++)); do
  svcname=svc$svcnum
  service_yaml $svcname $ip >> $yaml
  echo $svcname.$namespace.svc.$domain >> $names
  echo $ip.in-addr.arpa >> $ptrs
  echo _scale-port._tcp.$svcname.$namespace.svc.$domain >> $srvs
  ip=$(next_ip $ip) 
done

# Headless Services (yaml + a/srv lists)
for ((svcnum=1; svcnum<=$headless_services; svcnum++)); do
  svcname=hdls$svcnum
  service_yaml $svcname None >> $yaml
  echo $svcname.$namespace.svc.$domain >> $names
  echo _scale-port._tcp.$svcname.$namespace.svc.$domain >> $srvs
done

# Serviceless Pods (yaml)
for ((podnum=1; podnum<=$pods; podnum++)); do
  podname=pod$podnum
  pod_yaml $podname >> $yaml
done

# Apply scale object defintions
#

# First clean up the namespace, if it exists
kubectl delete namespace $namespace &> /dev/null
if [ $? -eq 0 ]; then
  echo Cleaning up existing namespace: $namespace
  while kubectl get namespaces $namespace &> /dev/null; do
    wait_indicator "Terminating (remaining: $(count_all_services) services, $(count_all_deployments) deployments, $(count_all_pods) pods)"
  done
  echo
  echo
fi

# Apply the scale object defintions
echo 'Applying scale object definitions to Kubernetes'
kubectl apply -f $yaml
echo

# Wait for all pods to be in a Running state
expected_pod_count=$((pods+services*pods_per_service+headless_services*pods_per_service))
echo Waiting for all $expected_pod_count pods to be ready:
count=$(count_running_pods)
until [ $count -eq $expected_pod_count ]; do
  count=$(count_running_pods)
  wait_indicator "$count/$expected_pod_count"
done
echo
echo

# Add dynamic IPs for pods/endpoints to the names list files
#

# Add endpoint A records to names list file
echo Adding endpoint A record names to $names
kubectl -n $namespace get endpoints -o=custom-columns=SVC:.metadata.name,IP:.subsets[0].addresses[*].ip | tail -n +2 | awk '{print $1" "$2}' | \
while IFS=' ' read -r svc_name ip_list; do
  ips=${ip_list//,/ }
  for ip in $ips; do
    echo ${ip//\./\-}.$svc_name.$namespace.svc.$domain >> $names
  done
done

# Add pod A records to names list file
echo Adding pod A record names to $names
kubectl -n $namespace get pods -o=custom-columns=IP:status.podIP | tail -n +2 | \
while read ip; do
    echo ${ip//\./\-}.$namespace.pod.$domain >> $names
done
echo

# Get prometheus service ip
#
prometheus_ip=$(kubectl get service prometheus -o jsonpath="{.spec.clusterIP}")

show_summary

# End of file

