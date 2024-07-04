#!/usr/bin/env bash
#
# (C) Copyright IBM Corp. 2020  All Rights Reserved.
#
# Script install Couchdb Operator through the Operator Lifecycle Manager (OLM) or via command line (CLI)
# application of kubernetes manifests in both an online and offline airgap environment.  This script can be invoked using
# `cloudctl`, a command line tool to manage Container Application Software for Enterprises (CASEs), or directly on an
# uncompressed CASE archive.  Running the script through `cloudctl case launch` has added benefit of pre-requisite validation
# and verification of integrity of the CASE.  Cloudctl download and usage istructions are available at [github.com/IBM/cloud-pak-cli](https://github.com/IBM/cloud-pak-cli).
#
# Pre-requisites:
#   oc or kubectl installed
#   sed installed
#   CASE tgz downloaded & uncompressed
#   authenticated to cluster
#
# Parameters are documented within print_usage function.

# ***** GLOBALS *****

# ----- DEFAULTS -----

# Command line tooling & path
kubernetesCLI="oc"
scriptName=$(basename "$0")
scriptDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Script invocation defaults for parms populated via cloudctl
action="install-operator-native"
caseJsonFile=""
casePath="${scriptDir}/../../.."
caseName="ibm-zen-operator-case"
inventory="zenOperatorSetup"
instance=""

# - optional parameter / argument defaults
dryRun=""
deleteCRDs=0
namespace=""
registry=""
pass=""
secret=""
user=""
inputcasedir=""
cr_system_status="betterThanYesterday"
recursive_catalog_install=0

# - variables specific to catalog/operator installation
caseCatalogName="ibm-zen-operator-catalog"
catalogNamespace="openshift-marketplace"
channelName="v1.0"
catalogDigest=":latest"

# - additional variables
WEBHOOK_ENABLED_CPD="${WEBHOOK_ENABLED_CPD:-true}"
OPERATOR_IMAGE="${OPERATOR_IMAGE:-ibm-zen-operator}"
OPERATOR_TAG="${OPERATOR_TAG:-v1.0.0}"
OPERATOR_REGISTRY="${OPERATOR_REGISTRY:-quay.io/opencloudio}"
entitledSecret="ibm-zen-operator-secret"
entitledRegistry="quay.io/opencloudio"
storageclass=""

# ***** ACTIONS *****


# ----- INSTALL ACTIONS -----

install_dependent_catalogs() {
    echo "-------------Installing dependent catalogs-------------"
    $kubernetesCLI apply -f "${casePath}"/inventory/"${inventory}"/files/deploy/install/common-services-catalog-source.yaml
	$kubernetesCLI apply -f "${casePath}"/inventory/"${inventory}"/files/deploy/install/common-services-subscription.yaml
}

install_operator_group() {
    echo "-------------Installing operator group-------------"
    sed -i -- "s/REPLACE_NAMESPACE/${namespace}/g" ${casePath}/inventory/${inventory}/files/deploy/install/operator-group.yaml
    $kubernetesCLI apply -f "${casePath}"/inventory/"${inventory}"/files/deploy/install/operator-group.yaml -n ${namespace}
}

# Installs the catalog source and operator group
install_catalog() {
   echo "-------------Installing catalog source-------------"
   validate_install_catalog

   local catsrc_file="${casePath}"/inventory/"${inventory}"/files/deploy/install/catalog-source.yaml

   # Verfy expected yaml files for install exit
   validate_file_exists "${catsrc_file}"

   # Apply yaml files manipulate variable input as required

   local catsrc_image_orig=$(grep "image:" "${catsrc_file}" | awk '{print$2}')
   echo "orig - ${catsrc_image_orig}"  
   # replace original registry with local registry
   local catsrc_image_mod="${registry}/$(echo "${catsrc_image_orig}" | sed -e "s/.*\///")"
   echo "mod - ${catsrc_image_mod}"

   # check if catalog digest available 
   image=$(echo $catsrc_image_mod | sed "s/.*\/\(.*\)/\1/g")
   imageName=$(echo $image | awk -F: '{print $1}')
   imageTag=$(echo $image | awk -F: '{print $2}')
   imageDigest=$(grep "image: $imageName$" "${casePath}"/inventory/metainv/resources.yaml -B 1 | grep digest | awk -F": " '{print $2}')

   # apply catalog source
   if [[ ! -z "$imageDigest" ]];then
       catsrc_image_mod_digest=$(echo ${catsrc_image_mod} | sed "s#\(.*\):.*#\1@${imageDigest}#g")
       sed <"${catsrc_file}" "s|${catsrc_image_orig}|${catsrc_image_mod_digest}|g" | $kubernetesCLI apply -f -
   else
       sed <"${catsrc_file}" "s|${catsrc_image_orig}|${catsrc_image_mod}|g" | $kubernetesCLI apply -f -
   fi 
}

# Install utilizing default OLM method
install_operator() {

    validate_install_args
    echo "-------------Installing via OLM-------------"
    install_operator_group

    #install_dependent_catalogs

    # link secret in openshift-marketplace
    if [[ "$secret" != "" ]]; then
       $kubernetesCLI get secret ${secret} -n ${namespace} --export -o yaml | $kubernetesCLI apply -n openshift-marketplace -f -
       $kubernetesCLI secrets link serviceaccount/default ${secret} --for=pull -n openshift-marketplace
       $kubernetesCLI apply -f "${casePath}"/inventory/"${inventory}"/files/deploy/install/catalog-source-staging.yaml
    else
       $kubernetesCLI apply -f "${casePath}"/inventory/"${inventory}"/files/deploy/install/catalog-source.yaml
    fi

	echo "Wait for catalog installation to complete"
	sleep 30

	$kubernetesCLI apply -f "${casePath}"/inventory/"${inventory}"/files/deploy/install/subscription.yaml -n ${namespace}
    echo "Wait for subscription to complete"
	sleep 60
	
    $kubernetesCLI apply -f "${casePath}"/inventory/"${inventory}"/files/deploy/service_account.yaml -n ${namespace}

    if [[ "$secret" != "" ]]; then
       $kubernetesCLI secrets link serviceaccount/ibm-zen-operator-serviceaccount ${secret} --for=pull -n ${namespace} 
    fi
    # restart pod to refresh secret
	oc delete pod -l control-plane=controller-manager

}

# Install utilizing default CLI method
install_operator_native() {
    if [ ! -z "$registry" ]; then
        OPERATOR_REGISTRY=$registry
    fi

    validate_install_args
   
    OPERATOR_IMAGE_FULL_PATH=${OPERATOR_REGISTRY}/${OPERATOR_IMAGE}:${OPERATOR_TAG}

    echo "Install Operator Native..."
    if [ -n "$OPERATOR_REGISTRY" ];then
        sed -i -- "s#quay.io/opencloudio#${OPERATOR_REGISTRY}#g" "${casePath}"/inventory/"${inventory}"/files/deploy/operator.yaml
    fi
    sed -i -- "s#WEBHOOK_ENABLED_CPD#false#g" "${casePath}"/inventory/"${inventory}"/files/deploy/operator.yaml
    #sed -i -- "s#\"ENTITLED_REGISTRY\"#\"${entitledRegistry}\"#g" "${casePath}"/inventory/"${inventory}"/files/deploy/operator.yaml
    # replace registry if provided, default registry for csv deployment
    #sed -i "s#image: .*\/#image: ${entitledRegistry}\/#g" "${casePath}"/inventory/"${inventory}"/files/deploy/operator.yaml
    sed -i -- "s#REPLACE_NAMESPACE#${namespace}#g" "${casePath}"/inventory/"${inventory}"/files/deploy/cluster_role_binding.yaml

    # remove pullPrefix from case, replace tag with digest
    if [[ -z "${pullPrefix}" ]];then 
        image=$(grep "image: " "${casePath}"/inventory/"${inventory}"/files/deploy/operator.yaml|head -n 1 | sed "s/image: .*\/\(.*\)/\1/g")
        imageName=$(echo $image | awk -F: '{print $1}')
        imageTag=$(echo $image | awk -F: '{print $2}')
        imageDigest=$(grep "image: .*$imageName$" "${casePath}"/inventory/metainv/resources.yaml -B 1 | grep digest | awk -F": " '{print $2}')
        if [[ -z "$imageDigest" ]];then
            echo "failed to get image digest"
            exit 1
        fi
        sed -i -- "s#\(image: .*\):.*#\1@${imageDigest}#g" "${casePath}"/inventory/"${inventory}"/files/deploy/operator.yaml
    fi

    echo "pre install"
    $kubernetesCLI apply -f "${casePath}"/inventory/"${inventory}"/files/deploy/crds/zen.cpd.ibm.com_zenservices.yaml
    $kubernetesCLI apply -f "${casePath}"/inventory/"${inventory}"/files/deploy/service_account.yaml -n ${namespace}
    $kubernetesCLI apply -f "${casePath}"/inventory/"${inventory}"/files/deploy/cluster_role.yaml
    $kubernetesCLI apply -f "${casePath}"/inventory/"${inventory}"/files/deploy/cluster_role_binding.yaml 

    if [[ "$secret" != "" ]]; then
       $kubernetesCLI secrets link ibm-zen-operator-serviceaccount ${secret} --for=pull -n ${namespace}
    fi
    
    echo "installing operator"
    $kubernetesCLI apply -f "${casePath}"/inventory/"${inventory}"/files/deploy/operator.yaml -n ${namespace}

}

# install operand custom resources
apply_custom_resources() {

cat << EOF | oc apply -f -
apiVersion: zen.cpd.ibm.com/v1
kind: ZenService
metadata:
  name: lite-cr
  namespace: ${namespace}
spec:
  storageClass: ${storageclass}
EOF
    
}

run_adm(){
    echo "***run adm in ${namespace}: to be removed after security hardening***"
    
    $kubernetesCLI apply -n ${namespace} -f "${casePath}"/inventory/"${inventory}"/files/deploy/adm.yaml
    $kubernetesCLI adm policy add-scc-to-user cpd-user-scc system:serviceaccount:${namespace}:cpd-viewer-sa
    $kubernetesCLI adm policy add-scc-to-user cpd-user-scc system:serviceaccount:${namespace}:cpd-editor-sa
    $kubernetesCLI adm policy add-scc-to-user cpd-zensys-scc system:serviceaccount:${namespace}:cpd-admin-sa
    $kubernetesCLI adm policy add-scc-to-user cpd-noperm-scc system:serviceaccount:${namespace}:cpd-norbac-sa
}

remove_adm(){
    $kubernetesCLI delete -f "${casePath}"/inventory/"${inventory}"/files/deploy/adm.yaml
    $kubernetesCLI adm policy remove-scc-from-user cpd-user-scc system:serviceaccount:${namespace}:cpd-viewer-sa
    $kubernetesCLI adm policy remove-scc-from-user cpd-user-scc system:serviceaccount:${namespace}:cpd-editor-sa
    $kubernetesCLI adm policy remove-scc-from-user cpd-zensys-scc system:serviceaccount:${namespace}:cpd-admin-sa
    $kubernetesCLI adm policy remove-scc-from-user cpd-noperm-scc system:serviceaccount:${namespace}:cpd-norbac-sa
}
# ----- UNINSTALL ACTIONS -----

uninstall_dependent_catalogs() {
    echo "-------------Uninstalling dependent catalogs-------------"
    $kubernetesCLI delete -f "${casePath}"/inventory/"${inventory}"/files/deploy/install/common-services-catalog-source.yaml
	$kubernetesCLI delete -f "${casePath}"/inventory/"${inventory}"/files/deploy/install/common-services-subscription.yaml
}

# deletes the catalog source and operator group
uninstall_catalog() {
    echo "-------------Uninstalling catalog-------------"
    $kubernetesCLI delete -f "${casePath}"/inventory/"${inventory}"/files/deploy/install/subscription.yaml
    $kubernetesCLI delete -f "${casePath}"/inventory/"${inventory}"/files/deploy/install/operator-group.yaml	
	$kubernetesCLI delete -f "${casePath}"/inventory/"${inventory}"/files/deploy/install/catalog-source.yaml
}

# Uninstall operator installed via OLM
uninstall_operator() {
    echo "-------------Uninstalling OLM-------------"
	
	uninstall_catalog

    uninstall_dependent_catalogs

    $kubernetesCLI delete -f "${casePath}"/inventory/"${inventory}"/files/deploy/olm-catalog/ibm-cp-data-operator/1.0.0/ibm-cp-data-operator.v1.0.0.clusterserviceversion.yaml
	$kubernetesCLI delete -f "${casePath}"/inventory/"${inventory}"/files/deploy/install/subscription.yaml -n ${namespace}

    delete_resources
}

# Uninstall operator installed via CLI
uninstall_operator_native() {

    echo "-------------Uninstall operator native-------------"
   
    $kubernetesCLI delete -f "${casePath}"/inventory/"${inventory}"/files/deploy/service_account.yaml 
    $kubernetesCLI delete -f "${casePath}"/inventory/"${inventory}"/files/deploy/cluster_role.yaml
    $kubernetesCLI delete -f "${casePath}"/inventory/"${inventory}"/files/deploy/cluster_role_binding.yaml

    delete_custom_resources

    $kubernetesCLI delete -f "${casePath}"/inventory/"${inventory}"/files/deploy/operator.yaml

    delete_resources

    remove_adm
}

delete_resources() {

    echo "-------------Deleting operator resources-------------"
    $kubernetesCLI delete secret "${secret}" --ignore-not-found=true
    $kubernetesCLI delete secret ibm-entitlement-key --ignore-not-found=true
}

delete_custom_resources() {
     echo "-------------Uninstall custom resources-------------"
     $kubernetesCLI delete -f "${casePath}"/inventory/"${inventory}"/files/deploy/crds/zen.cpd.ibm.com_zenservices.yaml
}

# ***** END ACTIONS *****

# Verifies that we have a connection to the Kubernetes cluster
check_kube_connection() {
    # Check if default oc CLI is available and if not fall back to kubectl
    command -v $kubernetesCLI >/dev/null 2>&1 || { kubernetesCLI="kubectl"; }
    command -v $kubernetesCLI >/dev/null 2>&1 || { err_exut "No kubernetes cli found - tried oc and kubectl"; }

    # Query apiservices to verify connectivity
    if ! $kubernetesCLI get apiservices >/dev/null 2>&1; then
        # Developer note: A kubernetes CLI should be included in your prereqs.yaml as a client prereq if it is required for your script.
        err_exit "Verify that $kubernetesCLI is installed and you are connected to a Kubernetes cluster."
    fi
}

parse_custom_dynamic_args() {
    _IFS=$IFS
    IFS=" "
    read -ra arr <<<"$@"
    IFS="$_IFS"
    arr+=("")
    idx=0
    v="${arr[${idx}]}"

    while [ "$v" != "" ]; do
        case $v in
         --storageclass)
            idx=$((idx + 1))
            v="${arr[${idx}]}"
            storageclass=${v}
            ;;
         *)
            err_exit "Invalid Option ${v}"
            ;;
        esac
        idx=$((idx + 1))
        v="${arr[${idx}]}"
    done
}
