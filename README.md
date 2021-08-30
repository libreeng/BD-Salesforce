# Salesforce Integration for Onsight Connect and Onsight Workspace

## Deployment

### Pre-requisites

- A deployment environment; the integration uses the *sfdx* tool to deploy updates, so a Scratch org or similar environment is required.
- The Salesforce CLI tools (aka, *sfdx*). These can be installed by visiting https://developer.salesforce.com/docs/atlas.en-us.sfdx_setup.meta/sfdx_setup/sfdx_setup_install_cli.htm.

### Optional: Creating a temporary Scratch Org

For quick testing or development, you can create a temporary Scratch Organization to host a Salesforce deployment. The Scratch Org is a baseline deployment with no data and only factory-default metadata. It can have a lifetime up to 30 days, after which any changes made to the Scratch Org are wiped out, after which you will need to re-deploy a new Scratch Org.

The following command line steps outline how to create a new Scratch Org and to deploy the Onsight integration code to it. These steps use the *sfdx* command line tool and must be executed from the root of the Salesforce git repo directory:

```
# Create new scratch org (will last 30 days before being lost)
sfdx force:org:create -f config/project-scratch-def.json -a MyScratchOrg --setdefaultusername --durationdays 30

# Authenticate against the new org (will launch a browser window and prompt you to login/enter a password):
sfdx auth:web:login
```

### Push and Configure

Assuming you have an environment available (e.g., sandbox or scratch org), the integration can be deployed with the following command (from the project's root directory):
```
sfdx force:source:push
``` 

### Configure Named Credentials

Upon successful push deployment to your environment, you must configure the two following named credentials using the Salesforce Setup UI. The Named Credentials store your Onsight API Key for use with Onsight APIs used by the integeration.

The path to the Named Credentials page is *https://<your_env_url>/lightning/setup/NamedCredential/home*.

- Onsight Connect URI
- Onsight Workspace URI

For both of the above Named Credentials, set the following fields as follows:
- *Identity Type*: Named Principal
- *Authentication Protocol*: Password Authentication
- *Username*: any non-blank value (not used, but can't be blank)
- *Password*: Your Onsight API Key (required)

## Using the Integration

Once installed, Work Orders will have a new 'Onsight' tab under the 'Feed' view:

![](images/OnsightTab.png)

Be sure to assign the Remote Expert and/or Field Worker fields in the Work Order's 'Details' view:

![](images/WorkOrderDetails.png)

### Launching Onsight Connect

Click one of the 'Connect' contact links in the 'Onsight' tab. This will launch the Onsight Connect application on your device, contacting the selected resource. The current Work Order ID will be associated with this Onsight Call, and the ID will also be applied to any assets recorded or captured during the call.

Upon concluding the Onsight Call, have Onsight upload any captured assets to Onsight Workspace.

Now, back in Salesforce, click the 'Import Assets' button. This will synchronize the current Work Order with your Onsight Workspace account, creating references within Salesforce to the corresponding Workspace documents/assets. Please note that the content of these Workspace documents is NOT copied into Salesforce; only references are made.
