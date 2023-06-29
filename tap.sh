#!/bin/bash

### Assumptions
#
#   tanzu-cli has been downloaded and expanded into $TANZU_CLI_HOME
#
#   tanzu-cluster-essentials has already been downloaded and unpacked to $TKG_UTIL/downloads/tanzu-cluster-essentials
#   the tce utils (imgpkg kbld kapp ytt) have been copied to $PATH (eg: /usr/local/bin)
#
#   You have done docker login for tanzu regisry and your private registry

#######  Environment

# TODO: Clean out exports!

export TAP_VERSION=1.5.0

export TAP_DIR=$HOME/tap
#export PATH=$TAP_DIR/bin:$PATH
TEMP=$TAP_DIR/tmp
TEMP_TAP_VALUES=${TEMP}/tap-values.yml

TANZU_NET_CREDS=$HOME/.sekrits/tanzunet_creds.yml

ROOT_CA_FILE=$HOME/certs/rootCA.crt

#
# Set the Repository where TAP will be pulled from.  This is
# either a local registry (eg: Harbor), remote (gcr), or tanzunet
#

# Use these settings with installing from a local repository
export INSTALL_REGISTRY_HOSTNAME=registry.planet10.lab
export INSTALL_REGISTRY_USERNAME=tanzu
export INSTALL_REGISTRY_PASSWORD=Tanzu1!!
export TARGET_REPOSITORY=tap/tap-packages

# Use these setting when installing fromm TanzuNet
# export INSTALL_REGISTRY_HOSTNAME=registry.tanzu.vmware.com/tanzu-application-platform/tap-packages
# export INSTALL_REGISTRY_USERNAME=
# export INSTALL_REGISTRY_PASSWORD=

# Developer settings.
export REGISTRY_SERVER=registry.planet10.lab
export REGISTRY_USERNAME=tanzu
export REGISTRY_PASSWORD=Tanzu1!!
export DEV_NAMESPACE=dev
export PROJECT_REPOSITORY=tap/projects

#weird setting for the tanzu cli (if everyone's supposed to do it, why isn't it the default?)
export TANZU_CLI_NO_INIT=true

export TANZU_CLI_HOME=$HOME/tanzu
export TKG_UTIL=$HOME/tkg

TAP_VALUES_FILE=./config/tap-values.yml # Generic yaml
TAP_VALUES_OVERLAY=./config/tap-values-overlay.yml # YTT overlay for generic yaml
TAP_VALUES_YTT=./config/tap-values-ytt.yml # With YTT annotations
TAP_VALUES_SCHEMA=./config/tap-values-value-schema.yml # YTT Schema
TAP_VALUES_VALUE_FILES=./config-values/ # directory with values files (no ytt annotation)

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
        if [[ ! $(kubectl get nodes | grep ${TAP_CLUSTER_NAME} | grep control-plane | grep Ready) ]]; then
            echo "lookup failed.  Logging in..."
            klogin ${TAP_CLUSTER_NAME}
        else
            echo "Context seems to be working"
        fi
    fi

    # Final test of context.  If it doesn't work here bail.
    if [[ ! $(kubectl get nodes | grep ${TAP_CLUSTER_NAME} | grep control-plane | grep Ready) ]]; then
        echo "Context still not working.  Exiting."
        exit 1
    fi

    echo "Validated"
}

function ready_or_exit() {
    if [[ ! $(kubectl get nodes | grep ${TAP_CLUSTER_NAME} | grep control-plane | grep Ready) ]]; then
        echo "We don't seem to be talking with the cluster ${TAP_CLUSTER_NAME}.  Exiting."
        exit 1
    fi
    echo "ready"
}

#TODO: check which version is there and what is available.  Install/upgrade as necessary.
function install-tanzu-cli() {
    local version=$( ls $TANZU_CLI_HOME/cli/core/ | grep v | awk '{ print $1 }' )
    local current_version=$( tanzu version | grep version | awk '{ print $2 }' )
    echo "Install Tanzu CLI:  found version $version (current version $current_version)"
    if [[ $version == $current_version ]]; then
        echo "tanzu already at version available in $TANZU_CLI_HOME"
    else
        sudo install $TANZU_CLI_HOME/cli/core/$version/tanzu-core-linux_amd64 /usr/local/bin/tanzu
        current_version=$( tanzu version | grep version | awk '{ print $2 }' )
        if [[ $version == $current_version ]]; then
            echo "tanzu installed"
            echo "installing plugins"
            #Install plugins ... do this even after init as that doesn't install everything
            tanzu plugin install --local $TANZU_CLI_HOME/cli all
            echo "done with plugin install, listing"
            tanzu plugin list
        else
            echo "tanzu cli version not at expected value ... something probably went wrong with the install :("
        fi
    fi
}

# Setup a newly created ${TAP_CLUSTER_NAME}
function setup_tap() {
    echo "Setting up for the tap install"
    kubectl create ns tap-install
    kubectl create ns grype

    tanzu secret registry add registry-secret \
        --username ${INSTALL_REGISTRY_USERNAME} --password ${INSTALL_REGISTRY_PASSWORD} \
        --server ${INSTALL_REGISTRY_HOSTNAME} \
        --export-to-all-namespaces --yes --namespace tap-install

    tanzu package repository add tanzu-tap-repository \
        --url ${INSTALL_REGISTRY_HOSTNAME}/${TARGET_REPOSITORY}:${TAP_VERSION} \
        --namespace tap-install
}

function run_ytt() {
    ytt -f $1 \
        -f $2 \
        -f $TAP_VALUES_VALUE_FILES \
        --data-value-file ca_cert_data=${ROOT_CA_FILE} \
        --data-values-file ${TANZU_NET_CREDS}
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
        exit 0
        ;;
    
    validate-tap-values | vtv )
        echo "validating the tap-values.yml ytt data processing"
        PLAIN=$(ytt -f tmp/tap-install-expected.yaml)
        RESULT=$(run_ytt $TAP_VALUES_YTT $TAP_VALUES_SCHEMA )
        diff <(echo "${PLAIN}") <(echo "${RESULT}")
        exit 0
        ;;
    
    write-tap-values | wtv )
        echo "writing the tap-values.yml ytt data processing"
        rm $TEMP_TAP_VALUES
        run_ytt $TAP_VALUES_YTT $TAP_VALUES_SCHEMA > $TEMP_TAP_VALUES
        exit 0
        ;;
    
    validate-tap-values-overlay | vtvo )
        echo "validating the tap-values.yml overlay processing"
        PLAIN=$(ytt -f tmp/tap-install-expected.yaml)
        RESULT=$(run_ytt $TAP_VALUES_FILE $TAP_VALUES_OVERLAY )

        diff <(echo "${PLAIN}") <(echo "${RESULT}")
        exit 0
        ;;
    
    write-tap-values-overlay | wtvo )
        echo "writing the tap-values.yml overlay processing"
        rm $TEMP_TAP_VALUES
        run_ytt $TAP_VALUES_FILE $TAP_VALUES_OVERLAY > $TEMP_TAP_VALUES
        exit 0
        ;;
    
    install-tanzu-cli )
        install-tanzu-cli
        exit 0
        ;;

    relocate-images | ri )
        echo $(imgpkg --version | grep version)
        RELOCATE_COMMAND="imgpkg copy -b registry.tanzu.vmware.com/tanzu-application-platform/tap-packages:${TAP_VERSION} --to-repo ${INSTALL_REGISTRY_HOSTNAME}/${TARGET_REPOSITORY} --include-non-distributable-layers"
        echo $RELOCATE_COMMAND
        exec $RELOCATE_COMMAND
        exit 0
        ;;
    
    create-cluster | cc )
        [[ -f $TKG_UTIL/bin/create-cluster-timed.sh ]] && $TKG_UTIL/bin/create-cluster-timed.sh ${TAP_CLUSTER_NAME}
        exit 0
        ;;

    # login to the cluster before doing this
    post-create-cluster-config | pccc )
        ready_or_exit
        #kubectl apply -f $TKG_UTIL/config/authorize-psp-for-service-accounts.yaml
        kubectl create clusterrolebinding default-tkg-admin-privileged-binding --clusterrole=psp:vmware-system-privileged --group=system:authenticated
        #kubectl apply -f config/pod-security-policy.yaml
        #$TKG_UTIL/bin/tce.sh install
        kubectl create secret generic kapp-controller-config \
                --namespace tkg-system \
                --from-file caCerts=${CERTS_HOME}/${ROOT_CA_FILE}
        KAPP_CONTROLLER_PO=$( kubectl get po -n tkg-system | grep kapp | awk '{ print $1 }' )
        echo "restarting kapp-controller $KAPP_CONTROLLER_PO"
        kubectl delete pod $KAPP_CONTROLLER_PO -n tkg-system
        exit 0
        ;;
esac

# Validate the env is ready before trying to do any of the following actions
validate-tap-env

# TAP LCM
case $1 in
        
    setup )
        setup_tap
        ;;

    install )
        echo "Installing TAP (version: ${TAP_VERSION})"
        echo "tanzu package install tap -p tap.tanzu.vmware.com -v ${TAP_VERSION} -n tap-install --values-file ${$TEMP_TAP_VALUES}"
        rm $TEMP_TAP_VALUES
        run_ytt $TAP_VALUES_YTT $TAP_VALUES_SCHEMA > $TEMP_TAP_VALUES
        tanzu package install tap -p tap.tanzu.vmware.com -v ${TAP_VERSION} -n tap-install --values-file $TEMP_TAP_VALUES
        ;;

    post-install-config | pic )
        echo "Create the dev environment: namespace=${DEV_NAMESPACE}"
        kubectl create ns ${DEV_NAMESPACE}
        tanzu secret registry add registry-credentials --server ${REGISTRY_SERVER} --username ${REGISTRY_USERNAME} --password ${REGISTRY_PASSWORD} --namespace ${DEV_NAMESPACE}
        kubectl apply -f config/dev-namespace-setup.yaml -n ${DEV_NAMESPACE}
        ;;

    install-tbs-full-deps | tbs-deps )
        # echo $(imgpkg --version | grep version)
        TBS_VERSION=$( tanzu package available list buildservice.tanzu.vmware.com --namespace tap-install  | grep buildservice | awk '{ print $2 }' )
        echo "Relocating images for TBS version ${TBS_VERSION}"
        # RELOCATE_COMMAND="imgpkg copy -b registry.tanzu.vmware.com/tanzu-application-platform/tap-packages:${TBS_VERSION} --to-repo ${INSTALL_REGISTRY_HOSTNAME}/${TARGET_REPOSITORY}"
        # echo $RELOCATE_COMMAND
        # exec $RELOCATE_COMMAND
        imgpkg copy -b registry.tanzu.vmware.com/tanzu-application-platform/full-tbs-deps-package-repo:${TBS_VERSION} --to-repo ${INSTALL_REGISTRY_HOSTNAME}/${TARGET_REPOSITORY}
        tanzu package repository add tbs-full-deps-repository --url ${INSTALL_REGISTRY_HOSTNAME}/${TARGET_REPOSITORY}:${TBS_VERSION} --namespace tap-install
        tanzu package install full-tbs-deps -p full-tbs-deps.tanzu.vmware.com -v ${TBS_VERSION} -n tap-install
        ;;

    update )
        rm ${TEMP}/tap-install-values-processed.yaml
        ytt -f ${VALUES_FILE} -f ${TANZU_NET_CREDS} > ${TEMP}/tap-install.yml
        tanzu package installed update tap -p tap.tanzu.vmware.com -v ${TAP_VERSION} --values-file ${TEMP}/tap-install-values-processed.yaml -n tap-install
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
        #check that this works
        ["$2"] && kubectl get app $2 -oyaml -n tap-install || echo "tap.sh details app_name"
        ;;

    * )
        echo "fallout"
        ;;
esac
