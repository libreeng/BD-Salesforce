import { LightningElement, api, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getConnectUriAsync from '@salesforce/apex/OnsightConnectController.getConnectUriAsync';
import importAssetsAsync from '@salesforce/apex/OnsightWorkspaceController.importAssetsAsync';
import USER_ID from '@salesforce/user/Id'; 
import EMAIL_FIELD from '@salesforce/schema/User.Email';
import WORK_ORDER_NUMBER_FIELD from '@salesforce/schema/WorkOrder.WorkOrderNumber';
import REMOTE_EXPERT_FIELD from '@salesforce/schema/WorkOrder.RemoteExpert__c';
import FIELD_WORKER_FIELD from '@salesforce/schema/WorkOrder.FieldWorker__c';
import CONTACT_NAME_FIELD from '@salesforce/schema/Contact.Name';
import CONTACT_EMAIL_FIELD from '@salesforce/schema/Contact.Email';


export default class Onsight extends NavigationMixin(LightningElement) {
    @api recordId;          // injected by our Aura "wrapper" component
    @api isPhone;           // injected by our Aura "wrapper" component
    @api isAndroid;         // injected by our Aura "wrapper" component
    importing;              // shows/hides our busy indicator during import

    // Inject the logged-in user's email address
    @track objUser = {};
    @wire(getRecord, { recordId: USER_ID, fields: [ EMAIL_FIELD ] })
    userData({error, data}) {
        if(data) {
            this.objUser = {
                email: data.fields.Email.value
            };
        }
    }
    
    // Inject details about the current WorkOrder, including the "Remote Expert" and "Field Worker" custom fields
    @track remoteExpertId = "";
    @track fieldWorkerId = "";
    @wire(getRecord, { recordId: '$recordId', fields: [ WORK_ORDER_NUMBER_FIELD, REMOTE_EXPERT_FIELD, FIELD_WORKER_FIELD ]})
    workOrderData({error, data}) {
        if (data) {
            this.remoteExpertId = getFieldValue(data, REMOTE_EXPERT_FIELD);
            this.fieldWorkerId = getFieldValue(data, FIELD_WORKER_FIELD);
        }
    }   
    @wire(getRecord, { recordId: '$remoteExpertId', fields: [ CONTACT_NAME_FIELD, CONTACT_EMAIL_FIELD ]})
    remoteExpert;
    @wire(getRecord, { recordId: '$fieldWorkerId', fields: [ CONTACT_NAME_FIELD, CONTACT_EMAIL_FIELD ]})
    fieldWorker;

    get remoteExpertAvailable() {
        const email = this.remoteExpertEmail;
        return email && email != this.objUser.email;
    }

    get remoteExpertName() {
        const name = getFieldValue(this.remoteExpert.data, CONTACT_NAME_FIELD);
        return name ? `${name}` : "";
    }

    get remoteExpertEmail() {
        return getFieldValue(this.remoteExpert.data, CONTACT_EMAIL_FIELD);
    }

    get remoteExpertLinkTitle() {
        const name = getFieldValue(this.remoteExpert.data, CONTACT_NAME_FIELD);
        return name ? `Connect to ${name}` : "";
    }

    get fieldWorkerAvailable() {
        const email = this.fieldWorkerEmail;
        return email && email != this.objUser.email;
    }

    get fieldWorkerName() {
        const name = getFieldValue(this.fieldWorker.data, CONTACT_NAME_FIELD);
        return name ? `${name}` : "N/A";
    }

    get fieldWorkerEmail() {
        return getFieldValue(this.fieldWorker.data, CONTACT_EMAIL_FIELD);
    }

    get fieldWorkerLinkTitle() {
        const name = getFieldValue(this.fieldWorker.data, CONTACT_NAME_FIELD);
        return name ? `Connect to ${name}` : "N/A";
    }

    /**
     * Get Platform ID needed by Onsight Connect.
     * 
     * @returns 
     */
    getPlatform() {
        if (this.isPhone) {
            return this.isAndroid ? "PC" : "iOS";
        }
        return "PC";
    }

    /**
     * Generate body for Onsight Connect API request.
     * 
     * @param {*} calleeEmail 
     * @returns 
     */
    createRequestBody(calleeEmail) {
        return {
            Platform: this.getPlatform(),
            email: this.objUser.email,
            calleeEmail,
            metadataItems: {
                salesforceWorkOrderId: this.recordId
            }
        };
    }

    /**
     * Called when user clicks one of the call links (to either the Remote Expert or Field Worker).
     * 
     * @param {*} event 
     */
    async handleConnectClick(event) {
        const email = event.target.dataset.email;
        if (email) {
            const requestBody = this.createRequestBody(email);
            const connectUri = await getConnectUriAsync({ requestBody: JSON.stringify(requestBody) });
            console.log("++Onsight Connect URI: " + connectUri);
            this.openOnsightConnect(connectUri, requestBody);
        }
    }

    /**
     * Called when user clicks the Import button. Initiates the Workspace document importing process.
     * 
     * @param {*} event 
     */
    async handleImport(event) {
        this.importing = true;

        const resultJson = await importAssetsAsync({ workOrderId: this.recordId });
        const result = JSON.parse(resultJson);
        if (result.error) {
            this.showFailure("Failed to import assets", result.error);
        }
        else {
            this.showSuccess(result.success);
        }

        this.importing = false;
    }

    /**
     * Launches Onsight Connect application on the current user's device.
     * 
     * @param {*} url the Onsight Connect call URL.
     * @param {*} requestBody body to submit to the Onsight Connect call URL. This will
     * include metadata associated with the current WorkOrder.
     */
    openOnsightConnect(url, requestBody) {
        if (url.includes("https://tools.ietf.org/html/rfc7231")) {
            // The URL returned by the backend indicates that Onsight cannot call the contact
            alert(`There was a problem trying to contact ${requestBody.calleeEmail}. Please use the Onsight Platform Manager to ensure this person is a member of your Onsight domain and try again.`);
        }
        else {
            // Onsight URL looks legit; open a new browser window to launch Connect app.
            this[NavigationMixin.Navigate]({
                type: 'standard__webPage',
                attributes: {
                    url: url
                }
            });
        }
    }

    /**
     * Show a green, successful toast message to the user.
     * @param {*} message 
     */
    showSuccess(message) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Success',
                message,
                variant: 'success',
            }),
        );
    }

    /**
     * Show a red, failure toast message to the user.
     * @param {*} title 
     * @param {*} message 
     */
    showFailure(title, message) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant: 'error',
            }),
        );        
    }
}
