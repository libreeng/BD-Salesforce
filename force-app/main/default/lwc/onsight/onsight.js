import { LightningElement, api, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { createRecord, getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import USER_ID from '@salesforce/user/Id'; 
import EMAIL_FIELD from '@salesforce/schema/User.Email';
import WORK_ORDER_NUMBER_FIELD from '@salesforce/schema/WorkOrder.WorkOrderNumber';
import REMOTE_EXPERT_FIELD from '@salesforce/schema/WorkOrder.RemoteExpert__c';
import CONTACT_NAME_FIELD from '@salesforce/schema/Contact.Name';
import CONTACT_EMAIL_FIELD from '@salesforce/schema/Contact.Email';
import ONSIGHT_DOMAIN_API_KEY_FIELD from '@salesforce/schema/OnsightDomain__c.API_Key__c';

const ONSIGHT_CONNECT_CALL_OBJECT = "OnsightConnectCall__c";
const ONSIGHT_WORKSPACE_DOCUMENT_OBJECT = "OnsightWorkspaceDocument__c";
const ONSIGHT_CONNECT_LAUNCH_URL = "https://onsight.librestream.com/oamrestapi/api/launchrequest";
const WORKSPACE_URL = "https://onsight-workspace-proxy.azurewebsites.net/workspace/documents";      // Workspace API doesn't support CORS; need to proxy access to it
const API_KEY = "AheUnSk9x2E2Gbrc0IxHAg.-c46bqVtDt39B83gRVqejMohOx-VXaVYM8lgU5VMe_8";   // TODO


export default class Onsight extends NavigationMixin(LightningElement) {
    @api recordId;
    @api isPhone;
    @api isAndroid;
    importing;
    otherSearchText = "";

    @track objUser = {};
    @track remoteExpertId = "";

    // TODO: will this work??
    @wire(getRecord, { fields: [ ONSIGHT_DOMAIN_API_KEY_FIELD ]})
    apiKey;

    // get current user's email address
    @wire(getRecord, { recordId: USER_ID, fields: [ EMAIL_FIELD ] })
    userData({error, data}) {
        if(data) {
            this.objUser = {
                email: data.fields.Email.value
            };
        }
    }
    
    @wire(getRecord, { recordId: '$recordId', fields: [ WORK_ORDER_NUMBER_FIELD, REMOTE_EXPERT_FIELD ]})
    workOrderData({error, data}) {
        if (data) {
            this.remoteExpertId = data.fields.RemoteExpert__c.value;
        }
    }

    @wire(getRecord, { recordId: '$remoteExpertId', fields: [ CONTACT_NAME_FIELD, CONTACT_EMAIL_FIELD ]})
    remoteExpert;

    get remoteExpertAvailable() {
        const email = this.remoteExpertEmail;
        return email && email != this.objUser.email;
    }

    get remoteExpertName() {
        const name = getFieldValue(this.remoteExpert.data, CONTACT_NAME_FIELD);
        return name ? `${name} - Remote Expert` : "";
    }

    get remoteExpertEmail() {
        return getFieldValue(this.remoteExpert.data, CONTACT_EMAIL_FIELD);
    }

    get remoteExpertLinkTitle() {
        const name = getFieldValue(this.remoteExpert.data, CONTACT_NAME_FIELD);
        return name ? `Connect to ${name}` : "";
    }

    getPlatform() {
        if (this.isPhone) {
            return this.isAndroid ? "Android" : "iOS";
        }
        return "PC";
    }

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

    async handleExpertClick(event) {
        const email = getFieldValue(this.remoteExpert.data, CONTACT_EMAIL_FIELD);
        if (email) {
            const requestBody = this.createRequestBody(email);
            const connectUri = await this.generateConnectUri(requestBody);
            console.log("++Onsight Connect URI: " + connectUri);
            this.openOnsightConnect(connectUri, requestBody);
        }
    }

    async handleFieldTechClick(event) {
        const requestBody = this.createRequestBody("fieldtech@cogswellsprockets.com");
        const connectUri = await this.generateConnectUri(requestBody);
        console.log("++Onsight Connect URI: " + connectUri);
        this.openOnsightConnect(connectUri, requestBody);
    }

    generateConnectUri(requestBody) {
        return new Promise((resolve, reject) => {
            let launchRequest = new XMLHttpRequest();
            launchRequest.addEventListener("readystatechange", function () {
                if (this.readyState == 4/*XMLHttpRequest.DONE*/) {
                    if (this.status == 200) {
                        const launchUri = this.responseText.replace(/"/g, '');
                        resolve(launchUri);
                    }
                    else if (this.status == 400) {
                        var errorResult = JSON.parse(this.responseText);
                        console.log("sendOCApiLaunchRequest: Launch request failed with error: " + this.responseText);
                        reject(errorResult);
                    }
                }
            });

            launchRequest.open("POST", ONSIGHT_CONNECT_LAUNCH_URL);
            launchRequest.setRequestHeader("Authorization", "ls Bearer: " + API_KEY);
            launchRequest.setRequestHeader("Content-Type", "application/json");
            const launchRequestBody = JSON.stringify(requestBody);
            launchRequest.send(launchRequestBody);
        });
    }

    handleBlur(event) {
        this.otherSearchText = event.target.value;
    }

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

    async handleImport(event) {
        this.importing = true;
        await this.doImport();
        this.importing = false;
    }

    async doImport() {
        // Always search by salesforceWorkOrderId
        let searchTerms = {
            "salesforceWorkOrderId": this.recordId
        };

        // Add additional search term if user has typed something in
        if (this.otherSearchText) {
            assets[this.otherSearchText] = null;
        }

        const assets = await this.findAssetsInWorkspaceAsync(searchTerms);

        // Map an Onsight Call document ID to its Salesforce Call object ID
        let onsightToCallObjId = {};

        for (let i = 0; i < assets.length; i++) {
            const asset = assets[i];
            let callObjId = onsightToCallObjId[asset.parentID];

            // Insert parent OnsightConnectCall if not already done so
            if (!callObjId) {
                const parentDoc = await this.getWorkspaceDocumentAsync(asset.parentID);
                if (parentDoc) {
                    callObjId = await this.insertCallIntoSalesforceAsync(parentDoc);
                    if (!callObjId) {
                        return;
                    }

                    onsightToCallObjId[asset.parentID] = callObjId;
                }
            }

            const sfDoc = await this.insertDocumentIntoSalesforce(callObjId, asset);
            if (!sfDoc) {
                return;
            }
        }

        this.showSuccess(`${assets.length} Onsight Connect asset(s) have been imported`);
    }

    findAssetsInWorkspaceAsync(searchTerms) {
        const searchEntries = Object.entries(searchTerms);
        let query = "";

        for (let i = 0; i < searchEntries.length; i++) {
            const [key, value] = searchEntries[i];
            if (i > 0) {
                query += " OR ";
            }

            // If value is null/undefined, it means we need to search all metadata fields for the key's value
            if (value) {
                query += `(externalMetadataName.1 = '${key}' AND externalMetadataValue.1 = '${value}')`;
            }
            else {
                query += `(externalMetadataValue = '${key}')`;
            }
        }

        return this.getDocumentsAsync(`?query=${query}`, responseText => JSON.parse(responseText).documents);
    }

    getWorkspaceDocumentAsync(documentId) {
        return this.getDocumentsAsync(`/${documentId}`, responseText => JSON.parse(responseText));
    }

    getDocumentsAsync(urlPath, resolver) {
        return new Promise((resolve, reject) => {
            let launchRequest = new XMLHttpRequest();
            launchRequest.addEventListener("readystatechange", function () {
                if (this.readyState == 4/*XMLHttpRequest.DONE*/) {
                    if (this.status == 200) {
                        resolve(resolver(this.responseText));
                    }
                    else if (this.status == 400) {
                        var errorResult = JSON.parse(this.responseText);
                        console.log("queryOnsightWorkspace: request failed with error: " + this.responseText);
                        reject(errorResult);
                    }
                }
            });
            
            launchRequest.open("GET", `${WORKSPACE_URL}${urlPath}`);
            launchRequest.setRequestHeader("X-Api-Key", API_KEY);
            launchRequest.send();
        });
    }

    /**
     * Inserts the given Onsight Workspace document (representing a completed Onsight Connect call)
     * into Salesforce.
     * 
     * @param {*} callDocument The Onsight Connect Workspace document to be inserted into Salesforce.
     */
    async insertCallIntoSalesforceAsync(callDocument) {
        const recordInput = { 
            apiName: ONSIGHT_CONNECT_CALL_OBJECT, 
            fields: {
                ID__c: callDocument.id,
                Name: callDocument.title,
                Work_Order__c: this.recordId
            }
        };

        try {
            const record = await createRecord(recordInput);
            return record.id;
        }
        catch (error) {
            // If this is a duplicate record error, quietly return the pre-existing record ID and continue
            const duplicateRecordId = this.extractDuplicateRecordId(error);
            if (duplicateRecordId) {
                return duplicateRecordId;
            }

            // Otherwise we can't continue
            console.log(`++insertCallIntoSalesforceAsync: failed to import call. Reason: ${error.body.message}`);
            this.showFailure("Onsight Call not imported", error.body.message);
            return null;
        }
    }

    /**
     * Inserts the given Workspace document into Salesforce.
     * 
     * @param {*} callObjId The ID of the OnsightConnectCall object to which this document will be added.
     * @param {*} wsDoc The Onsight Workspace document to insert into Salesforce (as an OnsightWorkspaceDocument). 
     */
    async insertDocumentIntoSalesforce(callObjId, wsDoc) {
        const recordInput = { 
            apiName: ONSIGHT_WORKSPACE_DOCUMENT_OBJECT, 
            fields: {
                Name: wsDoc.title,
                ID__c: wsDoc.id,
                Type__c: wsDoc.type,
                Description__c: wsDoc.description,
                External_Metadata__c: JSON.stringify(wsDoc.externalMetadata),
                ParentID__c: wsDoc.parentID,
                Download_URL__c: wsDoc.downloadUrl,
                Onsight_Connect_Call__c: callObjId
            }
        };

        try {
            const record = await createRecord(recordInput);
            return record.id;
        }
        catch (error) {
            // If this is a duplicate record error, quietly return the pre-existing record ID and continue
            const duplicateRecordId = this.extractDuplicateRecordId(error);
            if (duplicateRecordId) {
                return duplicateRecordId;
            }

            // Otherwise we can't continue
            console.log(`++insertDocumentIntoSalesforce: failed to import asset document. Reason: ${error.body.message}`);
            this.showFailure("Onsight Workspace document not imported", error.body.message);
            return null;
        }
    }

    /**
     * Extract the pre-existing record ID in a DUPLICATE_VALUE Salesforce API error.
     * If the given error is not a duplicate error, null is returned.
     * @param {*} error 
     */
     extractDuplicateRecordId(error) {
        if (!error || !error.body || !error.body.output || !error.body.output.errors || 
            error.body.output.errors.length === 0) {
            return null;
        }

        const underlyingError = error.body.output.errors[0];
        if (underlyingError.errorCode === "DUPLICATE_VALUE") {
            const pattern = /record with id\: (.+)$/;
            let matches = underlyingError.message.match(pattern);
            if (matches && matches.length === 2) {
                return matches[1];
            }
        }

        return null;
    }

    showSuccess(message) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Success',
                message,
                variant: 'success',
            }),
        );
    }

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
