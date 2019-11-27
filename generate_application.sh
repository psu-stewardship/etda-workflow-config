domain_name="dsrd.libraries.psu.edu"
config_env=${CONFIG_ENV-dev}
set -e
set -x

## Configure git
git config user.email "drone@drone-test.dsrd.libraries.psu.edu"
git config user.name "DroneCI"

branch_slugified=$(echo $DRONE_BRANCH | sed -e "s/[^[:alnum:]]/-/g" | tr -s "-" | tr A-Z a-z| sed -e "s/preview-//g")

vault_path="secret/app/etda_workflow/${config_env}"
vault_path_escaped=$(echo $vault_path | sed  's/[\/&]/\\&/g' )

if [ $config_env == "prod" ]; then 
    vault_mount_path="auth/k8s-dsrd-dev"
    echo "we aren't in prod yet. bailing early"
    exit 0
    fqdn=scholarsphere.$domain_name
else
    vault_mount_path="auth/k8s-dsrd-prod"
    fqdn=submit-etda-$branch_slugified.$domain_name
fi

vault_login_role="etda-workflow-${CONFIG_ENV:-dev}"

## copy the template if we need to
if [ ! -f argocd/$branch_slugified.yaml ]; then 
    cp template.yaml argocd/$branch_slugified.yaml
fi

# process the template
yq w argocd/$branch_slugified.yaml metadata.name etda-workflow-$branch_slugified -i
yq w argocd/$branch_slugified.yaml spec.destination.namespace etda-workflow-$branch_slugified -i
yq w argocd/$branch_slugified.yaml spec.source.helm.values.image.tag $DRONE_BUILD_NUMBER -i 
yq w argocd/$branch_slugified.yaml spec.source.helm.values.global.vault.path $vault_path -i
yq w argocd/$branch_slugified.yaml spec.source.helm.values.global.vault.role etda-workflow-$config_env -i 
yq w argocd/$branch_slugified.yaml spec.source.helm.values.fqdn $fqdn -i 
yq w argocd/$branch_slugified.yaml spec.source.helm.values.global.vault.mountPath $vault_mount_path -i

# Turn the values block into a string 
sed -i -e 's/[[:space:]]values:/values: |/g' argocd/$branch_slugified.yaml

## add the file to git
git add argocd/$branch_slugified.yaml
git commit -m "Adds deployment for $branch_slugified"
git push -u origin master

