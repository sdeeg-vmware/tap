TAPNS=tap-install

function tap-nudge() {
        echo "nudgeing ${1} ...\n"
        kubectl -n $TAPNS patch packageinstalls.packaging.carvel.dev $1 --type='json' -p '[{"op": "add", "path": "/spec/paused", "value":true}]}}'
        kubectl -n $TAPNS patch packageinstalls.packaging.carvel.dev $1 --type='json' -p '[{"op": "add", "path": "/spec/paused", "value":false}]}}'
        echo '...done\n'
}

tap-nudge $1
