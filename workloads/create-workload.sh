
export WORKLOAD_NS=development

case $1 in

    setup | ready | info )
        echo "Here is the output of things in namespace=$WORKLOAD_NS"
        kubectl get secrets,serviceaccount,rolebinding,pods,workload,configmap,limitrange -n $WORKLOAD_NS
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
