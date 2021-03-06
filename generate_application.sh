domain_name="dsrd.libraries.psu.edu"
config_env=${CONFIG_ENV-dev}

## Configure git
git config user.email "drone@drone-test.dsrd.libraries.psu.edu"
git config user.name "DroneCI"

branch_slugified=$(echo $DRONE_BRANCH | sed -e "s/[^[:alnum:]]/-/g" | tr -s "-" | tr A-Z a-z| sed -e "s/preview-//g")

vault_path="secret/app/etda_workflow/${config_env}"
vault_path_escaped=$(echo $vault_path | sed  's/[\/&]/\\&/g' )

if [ $config_env == "prod" ]; then 
    vault_mount_path="auth/k8s-dsrd-prod"
    echo "we aren't in prod yet. bailing early"
    exit 0
    fqdn=submit-etda.$domain_name
else
    vault_mount_path="auth/k8s-dsrd-dev"
    fqdn=submit-etda-$branch_slugified.$domain_name
fi

vault_login_role="etda-workflow-${CONFIG_ENV:-dev}"

initalize_app=false
## copy the template if we need to
if [ ! -f argocd/$branch_slugified.yaml ]; then 
    initalize_app=true
    cp template.yaml argocd/$branch_slugified.yaml
fi


# Turn the block into yaml before proccessing
sed -i -e 's/^\([[:space:]]*\)values: |/\1values:/g' argocd/$branch_slugified.yaml

function initalize_app {
    echo "initalizing app"
    yq w argocd/$branch_slugified.yaml metadata.name etda-workflow-$branch_slugified -i
    yq w argocd/$branch_slugified.yaml spec.destination.namespace etda-workflow-$branch_slugified -i
    yq w argocd/$branch_slugified.yaml spec.source.helm.values.image.tag $DRONE_BUILD_NUMBER -i 
    yq w argocd/$branch_slugified.yaml spec.source.helm.values.global.vault.path $vault_path -i
    yq w argocd/$branch_slugified.yaml spec.source.helm.values.global.vault.enabled true -i
    yq w argocd/$branch_slugified.yaml spec.source.helm.values.global.vault.role etda-workflow-$config_env -i 
    yq w argocd/$branch_slugified.yaml spec.source.helm.values.fqdn $fqdn -i 
    yq w argocd/$branch_slugified.yaml spec.source.helm.values.global.vault.mountPath $vault_mount_path -i
}

function update_app {
    echo "upating app"
    yq w argocd/$branch_slugified.yaml spec.source.helm.values.image.tag $DRONE_BUILD_NUMBER -i 
}

## we only update the image tag if the file has been copied.
if [ "$initalize_app" = true ]; then 
    initalize_app
else
    update_app
fi

# Turn the values block into a string 
sed -i -e 's/[[:space:]]values:/values: |/g' argocd/$branch_slugified.yaml

## add the file to git
git add argocd/$branch_slugified.yaml
git commit -m "Adds deployment for $branch_slugified"
git push -u origin master


set -e
# SYNC the application after push
if [ -z $ARGOCD_SERVER ] || [ -z $ARGOCD_AUTH_TOKEN ]; then
    echo "skipping argosync. missing required environemnt variables"
else
    echo "syncing app of apps"
    argocd --insecure app sync etda-workflow-apps || true
    retries=6
    ## The first sync usually fails due certificate objects coming up in a degrated state.
    echo "syncing app"
    until sync; do
        retries=$((retries-1))
        sleep 30
          if [ $retries -lt 1 ]; then
            exit 1
          fi
    done
    echo "waiting for app"
    argocd --insecure app wait etda-workflow-$branch_slugified || true
fi

# Fire off slack message if we are successful
# TODO if slack_webhook_url is set, but we didn't do an argocd sync what's the meaning of life?
if [ -z $SLACK_WEBHOOK_URL ]; then
    echo "skipping slack message. missing SLACK_WEBHOOK_URL environment variable"
else
    slack -a -t "Sync Complete" -e :rocket: -u 'Drone CI' "Drone Build <https://drone-test.dsrd.libraries.psu.edu/$DRONE_REPO/$DRONE_BUILD_NUMBER|$DRONE_BUILD_NUMBER> is complete. You can view this deployment at https://$fqdn"
fi
