# Name

IBM&reg; Cloud Pak for Data

# Introduction
## Summary
Your  enterprise has data. Lots of data. You need  to use your  data to generate meaningful insights.

But your data is useless if you can't trust  it or  access it. Cloud Pak for Data lets you  do both by enabling you  to connect  to your  data (no  matter  where it lives), govern it, and find it, so that you  can put  your  data to work  quickly and efficiently.

Learn more  in the https://www.ibm.com/analytics/cloud-pak-for-data

# Features
### Single, unified platform
Reduce your  time to value with a single platform that  combines data governance  and analytics designed for data stewards, data engineers, data scientists, and business analysts.
### Data virtualization
Create data sets from  disparate data sources so that you  can query  and use the data as if it came from  a single source.
### Integrated governance
Know  your  data inside and out.  Ensure that your  data is high quality, aligns with business objectives, and complies with  regulations. 
### Built in analytics and AI
Unearth  the meaning in your  data, whether  you  prefer to work  in JupyterPython Notebooks  or quickly create visualizations from the analytics dashboards. 


# Details
## Prerequisites
### Resources Required
Minimum scheduling capacity:

| Software | Memory (GB) | CPU (cores) | Disk (GB) | Nodes |
| --- | --- | --- | --- | --- |
| Cloud Pak for Data | 64 | 16 | 100 | 3 |
| **Total** | **64** | **16**  | **100**  | **3** |

## Configuration
If desired, you can set the consoleRoutePrefix parameter. This value is used as the subdomain in the URL for the Cloud Pak for Data landing page.

You need to set a password for the admin username. After the installation completes, login on the Cloud Pak for Data dashboard with the username "admin" and the password you have defined. 
## Installing
## Limitations
The installation process will not make any verification for available resources (memory, cpu) on the cluster. Make sure have enough resources available to deploy Cloud Pak for Data if you are running other applications on your cluster.

## Storage
Cloud Pak for Data is configured to use dynamic provisioning. The installation will require about 700GB of your storage. Make sure to select a storageclass with enough resource available.

## SecurityContextConstraints Requirements
CPD also defines custom SecurityContextConstraints objects which are used to finely control the permissions/capabilities needed to deploy Lite and other base components. The definition of the SCCs are shown below:

The following SCCs are bound to the custom SAs that we define. Specifics:
  
**cpd-user-scc** - has a predefined reserved UID range (cpd-viewer-sa and cpd-editor-sa bind to this out of box)

**cpd-zensys-scc** - runs as the UID 1000321000. user-home PVC is owned by this user. (cpd-admin-sa binds to this out of box)

**cpd-noperm-scc** - is a custom SCC which is similar to the restricted SCC. (cpd-norbac-sa binds to this out of box) 

## Documentation
 Documentation for Cloud Pak for Data can be found at [Cloud Pak for Data documentation](https://www.ibm.com/support/knowledgecenter/en/SSQNUZ).