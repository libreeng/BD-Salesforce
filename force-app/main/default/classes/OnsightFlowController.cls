/**
 * Asks the Onsight Flow API to generate a URL to 
 * Onsight Flow to Start a new Workflow based job.
 */
public with sharing class OnsightFlowController {
    /**
     * Returns the valid onsite workflows for the current group.
     */
    public static String token = 'eyJhbGciOiJSUzI1NiIsImtpZCI6ImI4N2QxYTFlMzNjYWI1ZTJjNTUzYjQwNGNkZTQ0OWYwIiwidHlwIjoiSldUIn0.eyJuYmYiOjE2Mzk0MzA4MDYsImV4cCI6MTYzOTQzNDQwNiwiaXNzIjoiaHR0cHM6Ly9hY2NvdW50cy5mbG93LmxpYnJlc3RyZWFtLmNvbSIsImF1ZCI6WyJodHRwczovL2FjY291bnRzLmZsb3cubGlicmVzdHJlYW0uY29tL3Jlc291cmNlcyIsIjViM2UwY2RiNjIyOGQ2ZDU3NTdiZDEyYiIsIjViMmQyNzc0YmYwOTE0Y2M3Yzk1OWJlYyJdLCJjbGllbnRfaWQiOiI2MTk2YzUwMTlhMmYxZDAwMDFlYmM3MzIiLCJpbnRvd2FyZS53b3JrZmxvcGx1cy50ZWFtIjoiY29nc3dlbGxzcHJvY2tldHMiLCJzY29wZSI6WyJodHRwczovL3d3dy53b3JrZmxvcGx1cy5jb20vYXV0aC9qb2IubW9kaWZ5IiwiaHR0cHM6Ly93d3cud29ya2Zsb3BsdXMuY29tL2F1dGgvam9iLnJlYWRfYWxsIiwiaHR0cHM6Ly93d3cud29ya2Zsb3BsdXMuY29tL2F1dGgvd29ya2Zsb3cuZXhlY3V0ZSIsImh0dHBzOi8vd3d3LndvcmtmbG9wbHVzLmNvbS9hdXRoL3dvcmtmbG93LnJlYWQiXX0.MIg7bxbKLA3qOLQB4AW62F28D91EKKNN1hRZ9p6PxGN6fN7nH6N3EXo39APLLPIowZUK-m3kQnQAamyD_JdZg_MEaLv2bYizhZVhXYtbenbMYIwRuLT03jYt0mJVMllxddlVBVzcd2DUiCYkJiZW77WwOCpUyod_raA1IkmR_Q7nXfXkaa8-JE5jpX9d7RGPHFFWmNz2xdHKn7fCdN0gn90h_qEROjEL2e0_fArPjBFU3qTeRDsr6vvWk7vFX7ezvIy6Z0A47Qk6ibE_oYxE3dKeIiw7TixyZfQmbq0tqJkacKByclw4OtdnWnrXfiMwsFeirxj_6cJ1vbTUlS0aNg';

    @AuraEnabled(cacheable=true)
    public static List<WorkFlow> getFlowUriAsync(String requestBody) {
        Http http = new Http();
        HttpRequest request = new HttpRequest();
        // Provide the Named Credentials
        request.setEndpoint('https://gateway.flow.librestream.com/workflows/v2');
        request.setMethod('GET');
        request.setHeader('Authorization', 'Bearer ' +getValidToken());
        request.setHeader('Content-Type', 'application/json');

        HttpResponse response = http.send(request);

        if (response.getStatusCode() >= 200 && response.getStatusCode() < 300) {
            String jsonResponse = response.getBody();
            return (List<WorkFlow>)JSON.deserialize(jsonResponse, List<WorkFlow>.class);
        }

        return null;
    }
    
    @AuraEnabled
    /**
    * will require using the Onsight Workspace API Key to return a valid Flow API token
    * from the TokenGenerator proxy/shim
    */
     public static String getValidToken(){
        return OnsightFlowController.token;
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
