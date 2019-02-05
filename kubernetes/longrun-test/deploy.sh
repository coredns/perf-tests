#!/bin/bash

show_help () {
cat << EOF

usage: $0 [-a] [-g] [-d] [-t] [-k] [-m]

   -a : Install the entire setup.

   -g : Install the latest golang.
   -d : Install the latest Docker.

   -t : Install the basic essential Kubernetes tools (Kubeadm, Kubectl, Kubelet).
   -k : Install Kubernetes (DinD)

   -m : Install Prometheus Operator

EOF
exit 0
}

[[ $# -eq 0 ]] && show_help

# Defaults
#

go_version="1.11.5"



function wait_indicator {
    spin='-\|/'
    for i in {0..3}; do
        i=$(( (i+1) %4 ))
        printf "\r   $1 ${spin:$i:1} \r"
        sleep .25
    done
}

function install_all
{
    install_golang
    install_docker
    install_k8s_tools
    install_kubernetes
    install_prometheus_operator
}


function install_golang ()
{
    sudo apt-get update > /dev/null
    wget https://dl.google.com/go/go${go_version}.linux-amd64.tar.gz > /dev/null
    sudo tar -xvf go${go_version}.linux-amd64.tar.gz > /dev/null
    rm -rf /usr/local/go
    sudo mv go /usr/local

    export PATH=$PATH:/usr/local/go/bin

    go version

    # Check if Go has been installed successfully
    if go version | grep -q '1.11.5'; then
        echo "Go has been installed successfully"
    else
        echo "Error installing Go"
        exit 0
    fi
}

function install_docker
{
    sudo apt-get update > /dev/null

    sudo apt-get install -y \
         apt-transport-https \
         ca-certificates \
         curl \
         gnupg-agent \
         software-properties-common >/dev/null

    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add - > /dev/null

    sudo add-apt-repository \
         "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
         $(lsb_release -cs) \
         stable"

    sudo apt-get update > /dev/null
    sudo apt-get install -y docker-ce > /dev/null

}

function install_k8s_tools
{
    sudo apt-get update > /dev/null && sudo apt-get install -y apt-transport-https curl > /dev/null
    curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add - > /dev/null
    cat <<EOF >/etc/apt/sources.list.d/kubernetes.list
    deb https://apt.kubernetes.io/ kubernetes-xenial main
EOF
    sudo apt-get update > /dev/null
    sudo apt-get install -y kubelet kubeadm kubectl > /dev/null
    sudo apt-mark hold kubelet kubeadm kubectl > /dev/null

    if kubeadm version | grep -q 'kubeadm version'; then
        echo "Kubernetes tools have been installed successfully"
    else
        echo "Error installing Kubernetes tools"
        exit 0
    fi
}


function install_kubernetes
{
    git clone https://github.com/kubernetes-sigs/kubeadm-dind-cluster.git ~/dind

    # Bring up the Kubernetes v1.13 cluster.
    ~/dind/fixed/dind-cluster-v1.13.sh up

}

function install_prometheus_operator
{
    cd
    # Install Ingress
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/mandatory.yaml
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/provider/baremetal/service-nodeport.yaml


    # Install Tiller
    kubectl -n kube-system create sa tiller
    kubectl create clusterrolebinding tiller --clusterrole cluster-admin --serviceaccount=kube-system:tiller

    # Install Helm.
    curl https://raw.githubusercontent.com/helm/helm/master/scripts/get > get_helm.sh
    chmod 700 get_helm.sh
    ./get_helm.sh
    helm init
    sleep 5s

    # Install the Prometheus Operator
    helm install --name prom --namespace monitoring stable/prometheus-operator

    # Update the label selector to `kube-dns`.
    kubectl -n kube-system patch svc prom-prometheus-operator-coredns -p '{"spec": {"selector": {"k8s-app": "kube-dns"}}}'

    HOSTIP=$(hostname -I | awk '{print $1;}')
    kubectl proxy --address ${HOSTIP} --accept-hosts='^.*$'

}


# Get Options
#
OPTIND=1 # Reset in case getopts has been used previously in the shell.
while getopts "?agdtkm" opt; do
    case "$opt" in
    \?)
        show_help
        ;;
    a)
        install_all
        ;;
    g)
        install_golang
        ;;
    d)
        install_docker
        ;;
    t)
        install_k8s_tools
        ;;
    k)
        install_kubernetes
        ;;
    m)
        install_prometheus_operator
        ;;
    esac
done
