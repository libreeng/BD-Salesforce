/**
 * Asks the Onsight Flow API to generate a URL to 
 * Onsight Flow to Start a new Workflow based job.
 */
public with sharing class OnsightFlowController {
    /**
     * Returns the valid onsite workflows for the current group.
     */
    
    @AuraEnabled(cacheable=true)
    public static List<WorkFlow> getFlowUriAsync(String requestBody) {
        Http http = new Http();
        HttpRequest request = new HttpRequest();
        // Provide the Named Credentials
        request.setEndpoint('https://gateway.flow.librestream.com/workflows/v2');
        request.setMethod('GET');
        request.setHeader('Authorization', 'Bearer ' + getFlowTokenAsync());
        request.setHeader('Content-Type', 'application/json');

        HttpResponse response = http.send(request);

        if (response.getStatusCode() >= 200 && response.getStatusCode() < 300) {
            String jsonResponse = response.getBody();
            return (List<WorkFlow>)JSON.deserialize(jsonResponse, List<WorkFlow>.class);
        }

        return null;
    }
    

    public static string getFlowTokenAsync() {
        Http http = new Http();
        HttpRequest request = new HttpRequest();
         // Provide the API Key
        request.setEndpoint('callout:Flow_Proxy_URI');
        request.setMethod('POST');
        request.setHeader('X-Api-Key', '{!$Credential.Password}');
        request.setHeader('Content-Type', 'application/json');
        request.setBody('{"teamName":"{!$Credential.Username}"}');
        HttpResponse response = http.send(request);
        if (response.getStatusCode() >= 200 && response.getStatusCode() < 300) {
            return response.getBody();
        }

        return null;
    }

    public class WorkFlow {
        @auraEnabled
        public String workflowId {get; set;}
        @auraEnabled
        public DateTime created {get;set;}
        @auraEnabled
        public DateTime lastUpdated {get;set;}
        @auraEnabled
        public String activeVersionId {get;set;}
        @auraEnabled
        public String teamName {get;set;}
        @auraEnabled
        public String name {get;set;}
        @auraEnabled
        public String description {get;set;}
        @auraEnabled
        public List<Version> versions {get;set;}
        @auraEnabled
        public Boolean isArchived {get;set;}
        public String workflowIdForDraft {get;set;}
        @auraEnabled
        public String workflowIdForApproval {get;set;}
        @auraEnabled
        public Boolean approvalsMigrated {get;set;}
    }
    
    public class Version {
        @auraEnabled
        public String versionId;
        @auraEnabled
        public String fileReference;
        @auraEnabled
        public Integer fileSize;
        @auraEnabled
        public DateTime uploaded;
        @auraEnabled
        public String authorId;
        @auraEnabled
        public String authorName;
        @auraEnabled
        public String versionNotes;
        @auraEnabled
        public String[] approvals;
        @auraEnabled
        public String mode;
        @auraEnabled
        public Boolean isArchived;
        @auraEnabled
        public String downloadSignature;
        @auraEnabled
        public DateTime downloadSignatureExpiry;
    }
}
