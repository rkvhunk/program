import sys,utils,kubernetes, argparse, time, asyncio, logging
from openshift.dynamic import DynamicClient
from kubernetes import config
from urllib3 import disable_warnings

def verify_cluster_component(component, global_meta, enable_hpa, wait):
    if enable_hpa.lower() not in ['true','false']:
        raise ValueError("enable_hpa value is incorrect. It should be true|false")

    if str(wait).lower() not in ['true','false']:
        raise ValueError("wait value is incorrect. It should be true|false")

    if "," in component:
        raise Exception("[ERROR] You can scale only one cluster component at a time.")

    if component not in ["scheduler"]:
        raise ValueError("You must specify a cluster component. The following cluster components support scaling: scheduler")

    if not all(key in global_meta.get(component) for key in ('cr_kind','cr_name','hpa_supported')) or global_meta.get(component).get('hpa_supported') in ['false', False]:
        raise ValueError(f"[ERROR] The '{component}' component does not support hpa configuration.")

def patch_cluster_hpa_resource(dyn_client, component, component_data, cluster_component_ns, enable_hpa) -> None:
    if isinstance(enable_hpa, str):
        enable_hpa = enable_hpa.lower() == "true"   # convert enable_hpa as boolean
    body = [{"op": "replace", "path": "/spec/autoScaleConfig", "value": enable_hpa}]
    print(f"[INFO] The '{component}' component is ready for patching the '{component_data['cr_kind']}' custom resource with hpa configurations.")
    try:
        utils.patch_namespaced_resource(dyn_client, component_data['cr_api']+'/'+component_data['cr_api_version'], component_data['cr_kind'], cluster_component_ns, component_data['cr_name'], body)
    except Exception as exception:
        print(f"[ERROR] Failed to patch the resource with hpa configurations for '{component}' component.")
        raise exception
    # return None

def apply_cluster_hpa_config(k8s_client, component, cluster_component_ns, release, enable_hpa, wait) -> None:

    dyn_client = DynamicClient(k8s_client)
    try:
        utils.check_namespace(dyn_client, cluster_component_ns)
        global_meta = utils.initialize_metadata_via_files(release)
        verify_cluster_component(component, global_meta, enable_hpa, wait)
    except Exception as exception:
        raise exception

    component_data = global_meta[component]

    # check whether cr exists or not
    try:
        utils.get_namespaced_resources(dyn_client, component_data['cr_api']+'/'+component_data['cr_api_version'], component_data['cr_kind'], cluster_component_ns, component_data['cr_name'], ignore_not_found=False)            
    except Exception as exception:
        print(f"[ERROR] Hit error when getting the CR {component_data['cr_name']} for {component}: {exception}")
        return exception

    try:
        # patch cr, for shared cluster component, there should be only one cr instance to be edited
        patch_cluster_hpa_resource(dyn_client, component, component_data, cluster_component_ns, enable_hpa)

        if isinstance(wait, str):
            wait = wait.lower() == "true"   # convert enable_hpa as boolean

        # wait for cr, for shared cluster component, there should be only one cr instance to wait
        if wait:
            print(f"Waiting for the status of the {component_data['cr_kind']} custom resource to be {component_data['status_success']}.\n")

            # sleep 30s to let the cr status change
            print("Start to wait CR instances status to be refreshed. Sleep 30s\n")
            time.sleep(30)

            utils.wait_for_cr_resources(dyn_client, cluster_component_ns, component, component_data, component_data['cr_name'])
    except Exception as exception:
        raise exception

    # return None

if __name__ == "__main__":
    #script start from here
    disable_warnings()

    # Disable output buffering to print message immediately
    sys.stdout = utils.Unbuffered(sys.stdout)

    try:
        k8s_client = kubernetes.config.new_client_from_config()
    except kubernetes.config.config_exception.ConfigException:
        print("[ERROR] The cpd-cli is not authenticated to the cluster. Re-run the login-to-ocp command.\n")
        exit(1)
    except Exception as exception:
        print(f"[ERROR] Could not aaply the hpa configuration of the cluster components. The apply-cluster-component-hpa-config command encountered the following error : {exception}")
        exit(1)

    #taking argument from the user
    parser = argparse.ArgumentParser(description='Getting the custom resources of the input components')
    parser.add_argument('--component', required=True, type=str, help='component: [String type] Accept one component each time, cluster components include scheduler, ibm-cert-manager and ibm-licensing.')
    parser.add_argument('--cluster_component_ns', required=True, type=str, help='[String type] The project where the shared cluster component is installed.')
    parser.add_argument('--release', required=True, help='[String type] The version of the Cloud Pak for Data software that is installed in the project.')
    parser.add_argument('--enable_hpa', required=True, help='enable_hpa: [Boolean] hpa enable/disable for component')
    parser.add_argument('--wait', default=True, required=False, help='wait: [Boolean] Specify whether to wait for the custom resource to be ready.')
    args = parser.parse_args()

    print('\n=========================== Running apply_cluster_component_hpa_config.py script. Start the log. =========================================\n')

    try:
        error = apply_cluster_hpa_config(k8s_client, args.component, args.cluster_component_ns, args.release, args.enable_hpa, args.wait)
        if error:
            print(f"[ERROR] Could not patch the hpa configuration of cluster component. The apply-cluster-component-hpa-config command encountered the following error : {error}")
            exit(1)
    except Exception as exception:
        print(f"[ERROR] Could not patch the hpa configuration of cluster component. The apply-cluster-component-hpa-config command encountered the following error : {exception}")
        logging.exception(exception)
        exit(1)

    print('\n=======================The apply_cluster_component_hpa_config.py script ran successfully. End of the log.===================================')