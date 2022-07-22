#!/bin/bash

#######  Environment

export TAP_VERSION=1.2.0

#set the path to use the tap binaries
#export PATH=$HOME/tap/bin:$PATH

export SECRETS_HOME=$HOME/.sekrits
export TANZU_NET_CREDS=tanzunet_creds.yaml
source $SECRETS_HOME/TanzuNet_creds  # TODO: Eliminate with ytt

# Use these settings with installing from a local repository
export INSTALL_REGISTRY_HOSTNAME=registry20.planet10.lab
export INSTALL_REGISTRY_USERNAME=tanzu
export INSTALL_REGISTRY_PASSWORD=Tanzu1!!
export TARGET_REPOSITORY=tap/tap-packages

# Use these setting when installing fromm TanzuNet
#export INSTALL_REGISTRY_HOSTNAME=registry.tanzu.vmware.com/tanzu-application-platform/tap-packages
#export INSTALL_REGISTRY_USERNAME=
#export INSTALL_REGISTRY_PASSWORD=


#weird setting for the tanzu cli (if everyone's supposed to do it, why isn't it the default?)
export TANZU_CLI_NO_INIT=true

export TANZU_CLI_HOME=$HOME/tanzu
export TKG_UTIL=$HOME/tkg

export VALUES_FILE=config/tap-cluster-values.yaml

export TAP_CLUSTER_NAME=tap-cluster

#######  Functions

# Validate we can talk to the cluster and attempt to login if necessary.
# Look for cluster extensions and attempt to install
function validate-tap-env() {
    echo "Validating the environment is ready for tap."

    echo "Checking that the context is pointing to ${TAP_CLUSTER_NAME} and that the api returns a value..."
    if [[ ! $(kubectl config get-contexts | grep ${TAP_CLUSTER_NAME}) ]]; then
        echo "${TAP_CLUSTER_NAME} doesn't exist in contexts ... attempting to login"
        klogin ${TAP_CLUSTER_NAME}
    fi
    
    if [[ ! $(kubectl config get-contexts | grep ${TAP_CLUSTER_NAME} | grep '*') ]]; then
        echo "${TKGS_NAMESPACE} context exists, but not selected.  Selecting ..."
        kubectl config use-context ${TAP_CLUSTER_NAME}
        echo "${TAP_CLUSTER_NAME} context selected.  Testing context ..."
        if [[ ! $(kubectl get nodes | grep ${TAP_CLUSTER_NAME}-control-plane) ]]; then
            echo "lookup failed.  Logging in..."
            klogin ${TAP_CLUSTER_NAME}
        else
            echo "Context seems to be working"
        fi
    else
        echo "${TAP_CLUSTER_NAME} context exists.  Testing context ..."
        if [[ ! $(kubectl get nodes | grep ${TAP_CLUSTER_NAME}-control-plane) ]]; then
            echo "lookup failed.  Logging in..."
            klogin ${TAP_CLUSTER_NAME}
        else
            echo "Context seems to be working"
        fi
    fi

    # Final test of context.  If it doesn't work here bail.
    if [[ ! $(kubectl get nodes | grep ${TAP_CLUSTER_NAME}-control-plane) ]]; then
        echo "Context still not working.  Exiting."
        exit 0
    fi

    echo "Validated"
}

function ready_or_exit() {
    if [[ ! $(kubectl get nodes | grep ${TAP_CLUSTER_NAME}-control-plane) ]]; then
        echo "We don't seem to be talking with the cluster ${TAP_CLUSTER_NAME}.  Exiting."
        exit 0
    fi
    echo "ready"
}

#TODO: check which version is there and what is available.  Install/upgrade as necessary.
function install-tanzu-cli() {
    local version=$( ls $TANZU_CLI_HOME/cli/core/ | grep v | awk '{ print $1 }' )
    local current_version=$( tanzu version | grep version | awk '{ print $2 }' )
    echo "Install Tanzu CLI:  found version $version (current version $current_version)"
    if [[ $version == $current_version ]]; then
        echo "tanzu alreay at version available in $TANZU_CLI_HOME"
    else
        echo "sudo install $TANZU_CLI_HOME/cli/core/$version/tanzu-core-linux_amd64 /usr/local/bin/tanzu"
    fi
}

# tanzu secret registry add tap-registry \
#   --username ${INSTALL_REGISTRY_USERNAME} --password ${INSTALL_REGISTRY_PASSWORD} \
#   --server ${INSTALL_REGISTRY_HOSTNAME} \
#   --export-to-all-namespaces --yes --namespace tap-install
function create-tap-registry-secret() {
    tanzu secret registry add tap-registry \
        --username ${TANZU_NET_USER} --password ${TANZU_NET_PASSWORD} \
        --server registry.tanzu.vmware.com \
        --export-to-all-namespaces --yes --namespace tap-install    
}

function create-registry20-secret() {
    tanzu secret registry add registry20-secret \
        --username ${INSTALL_REGISTRY_USERNAME} --password ${INSTALL_REGISTRY_PASSWORD} \
        --server ${INSTALL_REGISTRY_HOSTNAME} \
        --export-to-all-namespaces --yes --namespace tap-install
}

function install-package-repo() {
    tanzu package repository add tanzu-tap-repository \
        --url ${INSTALL_REGISTRY_HOSTNAME}/${TARGET_REPOSITORY}:${TAP_VERSION} \
        --namespace tap-install
}

# This create adds the carvel annotation
# function create-tap-registry-secret() {
# cat <<EOF | kubectl -n tap-install apply -f -
# apiVersion: v1
# kind: Secret
# metadata:
#   name: tap-registry
#   annotations:
#     secretgen.carvel.dev/image-pull-secret: ""
# type: kubernetes.io/dockerconfigjson
# data:
#   .dockerconfigjson: e30K
# EOF
# }

# Setup a newly created ${TAP_CLUSTER_NAME}
function setup_tap() {
    echo "Setting up for the tap install"
    kubectl create ns tap-install
    kubectl create ns grype
    #create-tap-registry-secret
    create-registry20-secret
    install-package-repo
}

#######  Main Entry

# Pre-TAP install commands
case $1 in

    test )
        if [[ ! $(kubectl get nodes | grep ${TAP_CLUSTER_NAME}-control-plane) ]]; then
            echo "lookup failed.  Logging in..."
        else
            echo "Context seems to be working"
        fi
        exit 1
        ;;
        
    install-tanzu-cli )
        install-tanzu-cli
        exit 1
        ;;

    reclocate-images | ri )
        imgpkg copy -b registry.tanzu.vmware.com/tanzu-application-platform/tap-packages:${TAP_VERSION} --to-repo ${INSTALL_REGISTRY_HOSTNAME}/${TARGET_REPOSITORY}
        exit 1
        ;;
    
    create-cluster )
        [[ -f $TKG_UTIL/bin/create-cluster-timed.sh ]] && $TKG_UTIL/bin/create-cluster-timed.sh ${TAP_CLUSTER_NAME}
        exit 1
        ;;

    post-create-cluster-config | pccc )
        ready_or_exit
        kubectl apply -f $TKG_UTIL/config/authorize-psp-for-service-accounts.yaml
        kubectl apply -f config/pod-security-policy.yaml
        $TKG_UTIL/bin/tce.sh install
        exit 1
        ;;
esac

validate-tap-env

# TAP LCM
case $1 in
        
    setup )
        setup_tap
        ;;

    install )
        echo "Installing TAP (version: ${TAP_VERSION})"
        echo "tanzu package install tap -p tap.tanzu.vmware.com -v ${TAP_VERSION} --values-file ${VALUES_FILE} -n tap-install"
        rm tap-install-values-processed.yaml
        ytt -f ${VALUES_FILE} -f ${SECRETS_HOME}/${TANZU_NET_CREDS} > tap-install-values-processed.yaml
        tanzu package install tap -p tap.tanzu.vmware.com -v ${TAP_VERSION} -n tap-install --values-file tap-install-values-processed.yaml
        ;;

    update )
        rm tap-install-values-processed.yaml
        ytt -f ${VALUES_FILE} -f ${SECRETS_HOME}/${TANZU_NET_CREDS} > tap-install-values-processed.yaml
        tanzu package installed update tap -p tap.tanzu.vmware.com -v ${TAP_VERSION} --values-file tap-install-values-processed.yaml -n tap-install
        ;;

    delete )
        tanzu package installed delete tap -n tap-install
        ;;

    status )
        kubectl get packageinstall -n tap-install
        # tanzu package installed list -n tap-install
        ;;

    watch )
        watch kubectl get packageinstall -n tap-install
        ;;
    
    details )
        #check that $2 exists
        kubectl get app $2 -oyaml -n tap-install
        ;;

    * )
        echo "fallout"
        ;;
esac
