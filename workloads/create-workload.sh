
export INSTALL_REGISTRY_HOSTNAME=registry20.planet10.lab
export INSTALL_REGISTRY_USERNAME=tanzu
export INSTALL_REGISTRY_PASSWORD=Tanzu1!!

export WORKLOAD_NS=sqlrunner

export GROUP_FOR_APP_VIEWER=system:serviceaccounts
export GROUP_FOR_APP_EDITOR=system:serviceaccounts

function setup_sa() {
cat <<EOF | kubectl -n $WORKLOAD_NS apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: tap-registry
  annotations:
    secretgen.carvel.dev/image-pull-secret: ""
type: kubernetes.io/dockerconfigjson
data:
  .dockerconfigjson: e30K
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: default
secrets:
  - name: registry-credentials
imagePullSecrets:
  - name: registry-credentials
  - name: tap-registry
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: default-permit-deliverable
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: deliverable
subjects:
  - kind: ServiceAccount
    name: default
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: default-permit-workload
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: workload
subjects:
  - kind: ServiceAccount
    name: default
EOF
}

function rbac_the_hard_way() {
cat <<EOF | kubectl -n $WORKLOAD_NS apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: dev-permit-app-viewer
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: app-viewer
subjects:
  - kind: Group
    name: $GROUP_FOR_APP_VIEWER
    apiGroup: rbac.authorization.k8s.io
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: $WORKLOAD_NS-permit-app-viewer
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: app-viewer-cluster-access
subjects:
  - kind: Group
    name: $GROUP_FOR_APP_VIEWER
    apiGroup: rbac.authorization.k8s.io
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: dev-permit-app-editor
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: app-editor
subjects:
  - kind: Group
    name: $GROUP_FOR_APP_EDITOR
    apiGroup: rbac.authorization.k8s.io
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: $WORKLOAD_NS-permit-app-editor
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: app-editor-cluster-access
subjects:
  - kind: Group
    name: $GROUP_FOR_APP_EDITOR
    apiGroup: rbac.authorization.k8s.io
EOF
}

case $1 in

    setup )
        kubectl create ns $WORKLOAD_NS
        tanzu secret registry add registry-credentials --server $INSTALL_REGISTRY_HOSTNAME --username $INSTALL_REGISTRY_USERNAME --password $INSTALL_REGISTRY_PASSWORD --namespace $WORKLOAD_NS
        setup_sa
        # tanzu rbac binding add -g $GROUP_FOR_APP_VIEWER -n $WORKLOAD_NS -r app-viewer
        # tanzu rbac binding add -g $GROUP_FOR_APP_EDITOR -n $WORKLOAD_NS -r app-editor
        rbac_the_hard_way
        ;;

    tanzu-java-web-app | tjwa | web-app )
        tanzu apps workload create tanzu-java-web-app \
          --app tanzu-java-web-app \
          --type web \
          --git-repo https://github.com/sample-accelerators/tanzu-java-web-app \
          --git-branch main \
          -n $WORKLOAD_NS
        ;;

    sqlrunner )
        tanzu apps workload create sqlrunner \
          --app sqlrunner \
          --type web \
          --git-repo https://github.com/sdeeg-vmware/sqlrunner \
          --git-branch main \
          -n $WORKLOAD_NS
        ;;
    
    * )
        echo "fallout"
        ;;
esac
