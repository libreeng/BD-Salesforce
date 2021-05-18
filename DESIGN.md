# Design Notes

## User Interface

This integration contains one central user interface element: the Lightning Web Component (LWC) 'onsight', located in the *force-app/main/default/lwc* directory.

This component is displayed under the 'Onsight' tab of the WorkOrder page. The tab is actually a Salesforce 'Quick Action' (see: *force-app/main/default/quickActions*). LWCs do not have support for Quick Actions; therefore, a small Aura component (*force-app/main/default/aura/auraonsight*) is used as a wrapper around our custom LWC. This Aura wrapper component allows the LWC to be displayed within a custom tab, and also provides automatic injection of contextual variables into the LWC (notably, the current WorkOrder ID and the user's device/platform).

The LWC's layout is simple: on the left is a list of contact links. On the right is an 'Import Assets' button.

### Contact Links

Each link on the left-hand side represents a resource associated with the current WorkOrder. In this implementation, the list is comprised of the Remote Expert and/or the designated Field Worker, both of which are custom fields (type: **Contact**) on the Work Order. If neither of these custom fields has been set, then no links will be displayed.

Clicking on a link will trigger a call to the Onsight Connect API via the **Onsight_Connect_URI** named credential. This named credential's Password field should contain the user's Onsight API key.

Assuming that the contact's email address can be corroborated with the Onsight domain, the API will return a Connect URI which is immediately opened, launching Onsight Connect on the user's device. The Connect call will automatically include the WorkOrder ID as a metadata field, meaning that any assets collected during the call will also be tagged with the ID, making them queryable through Onsight Workspace.

### Import Assets Button

The Import Assets button will initiate a synchronization between Salesforce and Onsight Workspace. This synchronization consists of querying for all Workspace documents tagged with the current WorkOrder ID and 'importing' a corresponding **OnsightWorkspaceDocument** object into Salesforce. The implementation does NOT import the acutal document content into Salesforce; rather, the **OnsightWorkspaceDocument** is simply a reference to the real document stored in Workspace.

## Apex Controllers

The LWC uses two Apex controllers to carry out much of its work. By using Apex controllers, the API calls to Onsight Connect and Onsight Workspace can both be secured through the use of Named Credentials.

### OnsightConnectController

The **OnsightConnectController** class calls the Onsight Connect API on behalf of the LWC, returning a URI that the LWC uses to launch the Onsight Connect application locally.

### OnsightWorkspaceController

The **OnsightWorkspaceController** class makes multiple calls to the Onsight Workspace API to fetch information about all documents associated with a given WorkOrder. It creates and inserts OnsightWorkspaceDocument and OnsightConnectCall objects into Salesforce as references to these Workspace documents.

## Data Model

### Custom Objects
There are two custom objects used by this integration:
- **OnsightConnectCall**: represents an Onsight Connect call initiated from the LWC and associated with a specific WorkOrder. 
- **OnsightWorkspaceDocument**: references an Onsight Workspace document associated with a particular Salesforce WorkOrder.

### WorkOrder Customizations
- Remote Expert: a custom **Contact** field used to designate a callable expert.
- Field Worker: a custom **Contact** field used to designate the field service worker responsible for carrying out the WorkOrder.
- OnsightConnectCalls: child relationship containing all Onsight Connect calls initiated from the WorkOrder's LWC UI. In turn, each **OnsightConnectCall** within this list will contain any **OnsightWorkspaceDocument**s associated with the call.

# Miscellaneous

Note that in order to make API calls to the Librestream domain, the following security configurations have been defined in this integration:
- cspTrustedSites
- remoteSiteSettings
- namedCredentials
