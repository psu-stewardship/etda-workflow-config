## takes environment vars from CI and puts them into an application spec

## hardcode domain we may want to set this in CI before running, so this is stubbed out here 
domain_name="dev.k8s.libraries.psu.edu"
config_env=${CONFIG_ENV:-dev}
config_branch=${CONFIG_BRANCH:-master}
image_repository=${IMAGE_REPOSITORY:-harbor.k8s.libraries.psu.edu/library/etda-workflow}


## configure git 
git config user.email "circle@dcircleci.com"
git config user.name "CircleCI"

## create sluggified branch
branch_slugified=$(echo $CIRCLE_BRANCH | sed -e "s/[^[:alnum:]]/-/g" | tr -s "-" | tr A-Z a-z| sed -e "s/preview-//g")

## Here we set the customizables based off branch name. we'll do all switching based off branch name?
if [ ${CIRCLE_BRANCH} == "master" ]; then
    app_name="etda-workflow-qa"
    dest_namespace="etda-workflow-qa"
    config_env="qa"
    env="qa"
    vault_mount_path=auth/k8s-dsrd-dev
    fqdn="etda-workflow-qa.dsrd.libraries.psu.edu"
    vault_path="secret/data/app/etda_workflow/${config_env}"
    vault_login_role="etda-workflow-qa"
else
    app_name="etda-workflow-$branch_slugified"
    dest_namespace="etda-workflow-$branch_slugified"
    config_env="dev"
    env=$branch_slugified
    vault_mount_path=auth/k8s-dsrd-dev
    fqdn=etda-workflow-$branch_slugified.$domain_name
    vault_path="secret/data/app/etda_workflow/${config_env}"
    vault_login_role="etda-workflow-${config_env}"
fi

initalize_app=false
if [ ! -f argocd/$branch_slugified.yaml ]; then
    initalize_app=true
    cp template.yaml argocd/$branch_slugified.yaml
fi

# Turn the block into yaml before proccessing
sed -i -e 's/^\([[:space:]]*\)values: |/\1values:/g' argocd/$branch_slugified.yaml

function initalize_app {
    yq w argocd/$branch_slugified.yaml metadata.name $app_name -i
    yq w argocd/$branch_slugified.yaml spec.destination.namespace $dest_namespace -i
    yq w argocd/$branch_slugified.yaml spec.source.helm.values.vault.mountPath $vault_mount_path -i
    yq w argocd/$branch_slugified.yaml spec.source.helm.values.image.tag $CIRCLE_SHA1 -i
    yq w argocd/$branch_slugified.yaml spec.source.helm.values.image.repository $image_repository -i
    yq w argocd/$branch_slugified.yaml spec.source.helm.values.fqdn $fqdn -i
    yq w argocd/$branch_slugified.yaml spec.source.helm.values.env $env -i
    yq w argocd/$branch_slugified.yaml spec.source.helm.values.global.vault.path $vault_path -i 
    yq w argocd/$branch_slugified.yaml spec.source.helm.values.serviceAccount.name $vault_login_role -i
    yq w argocd/$branch_slugified.yaml spec.source.helm.values.global.vault.role $vault_login_role -i
}

function update_app {
    yq w argocd/$branch_slugified.yaml spec.source.helm.values.image.tag $CIRCLE_SHA1 -i
    yq w argocd/$branch_slugified.yaml spec.source.helm.values.image.repository $image_repository -i
}

## we only update the image tag if the file has been copied.
if [ "$initalize_app" = true ]; then 
    initalize_app
else
    update_app
fi

# Turn the yaml into a block for helm values
sed -i -e 's/[[:space:]]values:/values: |/g' argocd/$branch_slugified.yaml

## add the file to git, and push it up 
git add argocd/$branch_slugified.yaml
added=$(git status --porcelain=v1| grep "^A\|^M")
git checkout $config_branch
if [[ $added ]]; then
    git commit -m "Adds deployment for $branch_slugified. Circle Build Number: $CIRCLE_BUILD_NUM"
    git push -u origin $config_branch
else
    echo "No files added. Continuing"
fi

function sync {
    argocd --insecure app sync $app_name > /dev/null
}

# SYNC the application after push 
if [ -z $ARGOCD_SERVER ] || [ -z $ARGOCD_AUTH_TOKEN ]; then
    echo "skipping argosync. missing required environemnt variables"
else
    echo "syncing app of apps"
    argocd --insecure app sync etda-workflow-apps || true
    retries=10
    ## The first sync usually fails due certificate objects coming up in a degrated state.
    echo "syncing app"
    until sync; do
        retries=$((retries-1))
        echo "."
        sleep 3
          if [ $retries -lt 1 ]; then
            exit 1
          fi
    done
    echo "waiting for app"
    argocd --insecure app wait $app_name || true
fi

# Fire off slack message if we are successful
# TODO if slack_webhook_url is set, but we didn't do an argocd sync what's the meaning of life?
if [ -z $SLACK_WEBHOOK ]; then 
   echo "skipping slack message. missing SLACK_WEBHOOK_URL environment variable"
else
   export SLACK_WEBHOOK_URL=$SLACK_WEBHOOK
   slack -a -t "Sync Complete" -e :rocket: -u 'CircleCI' "ArgoCD Sync Complete: You can view this deployment at https://$fqdn"
fi




