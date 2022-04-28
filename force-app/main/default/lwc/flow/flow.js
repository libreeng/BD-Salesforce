import { getRecord, getFieldValue, updateRecord } from 'lightning/uiRecordApi';
import { LightningElement, track, wire, api } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import GetFlowUriAsync from "@salesforce/apex/OnsightFlowController.getFlowUriAsync";
import ImportFlowJobsAsync from '@salesforce/apex/OnsightFlowController.importFlowJobsAsync';

import CONTACT_EMAIL_FIELD from '@salesforce/schema/Contact.Email';
import FIELD_WORKER_FIELD from '@salesforce/schema/WorkOrder.FieldWorker__c';
import WORK_FLOW_SELECTED_FIELD from '@salesforce/schema/WorkOrder.Work_Flow_Selected__c';

export default class Flow extends LightningElement {

    @api recordId; 
    
    importing;              // shows/hides our busy indicator during import
    workFlowOptions = [];

    @track displayBeginWorkflow;
    @track fieldWorkerId = "";
    @track selectedWorkFlow = '';
    @track value;

    @api isPhone;         // injected by our Aura "wrapper" component
    @api isAndroid;         // injected by our Aura "wrapper" component
    
    /**
     * Get the field worker data and sets the valid user
     * to disable the 'Begin Workflow' button if necessary
     */
    @wire(getRecord, { recordId: '$recordId', fields: [ FIELD_WORKER_FIELD ]})
    async WiredFieldWorkerData({error, data}) {
        if (data && data !== undefined) {
            this.fieldWorkerId = await getFieldValue(data, FIELD_WORKER_FIELD);
            if (this.fieldWorkerId == null) {
                this.displayBeginWorkflow = false;
                this.workFlowOptions = []; 
            } else {
                this.displayBeginWorkflow = true;
            }
        }
    } 

    @wire(getRecord, { recordId: '$fieldWorkerId', fields: [ CONTACT_EMAIL_FIELD ]})
    fieldWorker;

    get fieldWorkerEmail() {
        return getFieldValue(this.fieldWorker.data, CONTACT_EMAIL_FIELD);
    }

    /**
     * Populates the Workflow drop down based on the currently
     * selected field worker.
     */
    @wire(GetFlowUriAsync, {requestBody: '$fieldWorkerEmail'})
    WiredGetFlowUriAsync({ error, data }) {
        this.workFlowOptions = [];
        this.displayBeginWorkflow = false;
        if (data) {
            try {
                let options = [];
                data.forEach(key => {
                    if (key.workflowId !== undefined) {
                        options.push({ label: key.name, value: key.workflowId  });
                    }
                });
                if (options.length == 0 && this.selectedWorkFlow != '') {
                    this.showFailure("No available workflows. Please ensure the assigned Field Worker has been given access to workflows in the Flow Dashboard.", error);
                }
                this.workFlowOptions = options;

                this.workFlowOptions.forEach(option => {
                    if (option.value === this.selectedWorkFlow) {
                        this.displayBeginWorkflow = true;
                    }
                });

            } catch (error) {
                this.showFailure("Failed to load workflows", error);
            }
        } else {
            this.showFailure("Failed to load workflows");
        }
    }

    /**
     * Sets workflow dropdown based on the 
     * selectedWorkFlow on the Work Order object.
     */
    @wire(getRecord, { recordId: '$recordId', fields: [ WORK_FLOW_SELECTED_FIELD ]})
    async WiredWorkFlowData({error, data}) {
        if (data && data !== undefined) {
            this.selectedWorkFlow = await getFieldValue(data, WORK_FLOW_SELECTED_FIELD);
            this.value = this.selectedWorkFlow;
        } else if (error && error !== undefined) {
            this.showFailure("Failed to load selected workflow");
        }
    }

    /**
     * Sets selectedWorkFlow on the Work Order object 
     * so it will persist on page reload.
     */
    handleWorkFlowChange(event){
        const fields = {};
        fields.Id = this.recordId;
        fields[WORK_FLOW_SELECTED_FIELD.fieldApiName] = event.target.value;
        const recordInput = { fields };

        updateRecord(recordInput).then(() => {
            return refreshApex(this.recordId);
          }).catch((error) => {
            this.showFailure("Failed to update work order", error);
        });
    }

    /**
     * Generate flow v3 URL based on the selected work flow
     * in the WorkFlow dropdown.
     */
    handleClick(){
        window.open('https://web.flow.librestream.com/new/' + this.selectedWorkFlow + '?sfWorkOrderId=' + this.recordId);
    }

    /**
     * Imports all the completed workflow jobs 
     * that have the current work order id as metadata.
     */
    async handleImportCompletedWorkFlows(event) {
        this.importing = true;

        const resultsJson = await ImportFlowJobsAsync({ workOrderId: this.recordId });
        resultsJson.forEach(resultJson => {
            const result = JSON.parse(resultJson);
            if (result.error) {
                this.showFailure("Failed to import Completed Work Flows", result.error);
            } else {
                this.showSuccess(result.success);
            }
        });

        this.importing = false;
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