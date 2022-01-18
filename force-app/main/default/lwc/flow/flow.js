import { LightningElement, track, wire, api } from 'lwc';

import WORK_FLOW_SELECTED_FIELD from '@salesforce/schema/WorkOrder.Work_Flow_Selected__c';
import { getRecord, getFieldValue, updateRecord } from 'lightning/uiRecordApi';
import Objects_Type from "@salesforce/apex/OnsightFlowController.getFlowUriAsync";
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';

export default class Flow extends LightningElement {

    @api recordId; 

    @track selectedWorkFlow = '';
    @track l_All_WorkFlows;
    @track WorkFlowOptions;
    @track value;

    @wire(Objects_Type, {})
    WiredObjects_Type({ error, data }) {
        if (data) {
            try {
                this.l_All_WorkFlows = data;
               let options = [];
                data.forEach(key => {
                    if (key.activeVersionId !== undefined)
                    {
                        options.push({ label: key.name, value: key.activeVersionId  });
                    }
                });

                this.WorkFlowOptions = options;

            } catch (error) {
                this.showFailure("Failed to load workflows", error);
            }
        } else {
            this.showFailure("Failed to load workflows");
        }
    }

    @wire(getRecord, { recordId: '$recordId', fields: [ WORK_FLOW_SELECTED_FIELD ]})
    async workOrderData({error, data}) {
        if (data && data !== undefined) {
            this.selectedWorkFlow = await getFieldValue(data, WORK_FLOW_SELECTED_FIELD);
            this.value = this.selectedWorkFlow;
        } else if (error && error !== undefined) {
            this.showFailure("Failed to load selected workflow");
            console.log(error);
        }
    }

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

    handleClick(){
        // get picklist value and generate flow v3 URL
        window.open('https://web.flow.librestream.com/new/' + this.selectedWorkFlow + '?sfWorkOrderId=' + this.recordId);
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