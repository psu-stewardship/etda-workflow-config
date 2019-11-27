domain_name="dsrd.libraries.psu.edu"
config_env=${CONFIG_ENV-dev}
set -e

## Configure git
git config user.email "drone@drone-test.dsrd.libraries.psu.edu"
git config user.name "DroneCI"

branch_slugified=$(echo $DRONE_BRANCH | sed -e "s/[^[:alnum:]]/-/g" | tr -s "-" | tr A-Z a-z| sed -e "s/preview-//g")

vault_path="secret/app/etda_workflow/${config_env}"
vault_path_escaped=$(echo $vault_path | sed  's/[\/&]/\\&/g' )

if [ $config_env == "prod" ]; then 
    echo "we aren't in prod yet. bailing early"
    exit 0
    fqdn=scholarsphere.$domain_name
else
    fqdn=submit-etda-$branch_slugified.$domain_name
fi

vault_login_role="etda-workflow-${CONFIG_ENV:-dev}"

## copy the template if we need to
if [ ! -f argocd/$branch_slugified.yaml ]; then 
    cp template.yaml argocd/$branch_slugified.yaml
fi

# process the template
yq w argocd/$branch_slugified.yaml spec.metadata.name etda-workflow-$branch_slugified -i
yq w argocd/$branch_slugified.yaml spec.source.helm.values.image.tag $DRONE_BUILD_NUMBER -i 
yq w argocd/$branch_slugified.yaml global.vault.path -i
yq w argocd/$branch_slugified.yaml global.vault.role etda-workflow-$config_env -i 
yq w argocd/$branch_slugified.yaml spec.ingress.hosts.0 $fqdn -i 
yq w argocd/$branch_slugified.yaml spec.ingress.tls.0.hosts.0 $fqdn -i 
yq w argocd/$branch_slugified.yaml spec.ingress.tls.0.secretName $fqdn -i 

## add the file to git
git add argocd/$branch_slugified.yaml
git commit -m "Adds deployment for $branch_slugified"
git push -u origin master

