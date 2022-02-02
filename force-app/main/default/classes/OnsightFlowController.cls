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
        request.setEndpoint('https://accounts.flow.librestream.com/api/team/user');
        request.setMethod('GET');
        request.setHeader('Authorization', 'Bearer ' + getFlowTokenAsync());
        request.setHeader('Content-Type', 'application/json');

        HttpResponse response = http.send(request);

        User matchingUser = null;
        List<User> users;

        // get all users for team
        if (response.getStatusCode() >= 200 && response.getStatusCode() < 300) {
            String jsonResponse = response.getBody();
            users =  (List<User>)JSON.deserialize(jsonResponse, List<User>.class);
        }

        for (user u : users) {
            if (u.emailAddress == requestBody) {
                matchingUser = u;
                break;
            }
        }

        List<WorkFlow> workFlowsAllowed = new List<WorkFlow>();
        if (matchingUser == null) {
            // if no matching user return no workFlows
            return workFlowsAllowed;
        }

        // get all workflows that can be assigned to selected field worker
        // if workflow has permissions the userid will be listed in liveObjectIds
        for (WorkFlow workFlow : getWorkFlows()) {
            if (workFlow.liveObjectIds != null && workFlow.liveObjectIds.size() > 0) {
                for (String liveObjectId : workFlow.liveObjectIds) {
                    if (liveObjectId == matchingUser.userId) {
                        workFlowsAllowed.add(workFlow);
                        break;
                    }
                }
            } else {
                workFlowsAllowed.add(workFlow);
            }
        }
        // return only assignable workflows for selected field worker
        return workFlowsAllowed;
    }

    private static List<WorkFlow> getWorkFlows() {
        Http http = new Http();
        HttpRequest request = new HttpRequest();

        // Provide the Named Credentials
        request.setEndpoint('https://gateway.flow.librestream.com/workflows/v2');
        request.setMethod('GET');
        request.setHeader('Authorization', 'Bearer ' + getFlowTokenAsync());
        request.setHeader('Content-Type', 'application/json');

        HttpResponse response = http.send(request);

        List<WorkFlow> workFlows;

        if (response.getStatusCode() >= 200 && response.getStatusCode() < 300) {
            String jsonResponse = response.getBody();
            workFlows = (List<WorkFlow>)JSON.deserialize(jsonResponse, List<WorkFlow>.class);
        }
        return workFlows;
    }

    private static List<FlowReport> getReportsFromCompletedWorkFlowJobs(List<WorkFlowJob> workFlowJobs, Id workOrderId) {
        List<FlowReport> flowReports = new List<FlowReport>();
        for (WorkFlowJob workFlowJob : workFlowJobs) {
            if (workFlowJob.completedReportURL != null && workFlowJob.completedReportURL != '') {
                Http h = new Http();
                HttpRequest req = new HttpRequest();
                req.setEndpoint(workFlowJob.completedReportURL);
                req.setMethod('GET');
                req.setHeader('Content-Type', 'application/pdf');
                req.setCompressed(true);
                req.setTimeout(60000);
                HttpResponse res  = h.send(req);
                FlowReport workFlowReport = new FlowReport();
                workFlowReport.blobData = EncodingUtil.base64Encode(res.getBodyAsBlob());
                workFlowReport.jobTitle = workFlowJob.metadata.jobTitle;
                workFlowReport.workOrderId = Id.valueOf(workOrderId);
                flowReports.add(workFlowReport);
            }
        }
        return flowReports;
    }

    private static Integer insertCompletedReportIntoSalesforce(List<FlowReport> flowReports, Id workOrderId) {
        List<ContentDocument> contentDocumentsToDelete = new List<ContentDocument>();
        for (ContentDocumentLink contentDocumentLink : [
            SELECT
              ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId=:workOrderId
        ]) {
            contentDocumentsToDelete.add(new ContentDocument(
            Id = contentDocumentLink.ContentDocumentId
          ));
        }
        delete contentDocumentsToDelete;

        for (FlowReport flowReport : flowReports) {
            ContentVersion cv = new ContentVersion();
            cv.ContentLocation = 'S';
            cv.Title = flowReport.jobTitle;
            cv.PathOnClient = flowReport.jobTitle + '.flow.pdf';
            cv.VersionData = EncodingUtil.base64Decode(flowReport.blobData);
            insert cv;

            ContentDocumentLink cdl = new ContentDocumentLink();
            cdl.ContentDocumentId = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id =: cv.Id].ContentDocumentId;
            cdl.LinkedEntityId = flowReport.workOrderId;
            cdl.ShareType = 'I';
            insert cdl;
        }
        return flowReports.size();
    }

    @AuraEnabled
    public static List<String> importFlowJobsAsync(Id workOrderId) {
        List<String> results = new List<String>();
        try {
            // get all workflow jobs for team
            List<WorkFlowJob> allWorkFlowJobs = getAllWorkFlowJobs();
            List<WorkFlowJob> allCompletedJobsForWorkOrder = new List<WorkFlowJob>();

            // get all workflow jobs with metadata for workorder
            for (WorkFlowJob workFlowJob : allWorkFlowJobs) {
                String sfWorkOrderId = workFlowJob.metadata.metadata.get('sfWorkOrderId');
                String sfWorkOrderIdStr = Id.valueOf(workOrderId);
                if (sfWorkOrderId == sfWorkOrderIdStr) {
                    allCompletedJobsForWorkOrder.add(workFlowJob);
                }
            }

            // get all workflow jobs by Id for details
            // this is required if you need to get all the details, if not just call all jobs
            List<WorkFlowJob> allCompletedJobsForWorkOrderWithDetails = new List<WorkFlowJob>();
            for (WorkFlowJob workFlowJob : allCompletedJobsForWorkOrder) {
                if (workFlowJob.metadata.status == 'Completed') {
                    allCompletedJobsForWorkOrderWithDetails.add(getAllWorkFlowJobsWithDetails(workFlowJob.jobId));
                }
            }

            // download the report data for workflow jobs for the work order
            for (WorkFlowJob workFlowJob : allCompletedJobsForWorkOrderWithDetails) {
                ReportResponse completedReport = getCompletedReport(workFlowJob.jobId);
                if (completedReport != null) {
                    workFlowJob.completedReportURL = completedReport.reportUrl;
                }
            }

            // download the pdf blob using the completedReportURL
            List<FlowReport> completedFlowJobReportsToInsert = getReportsFromCompletedWorkFlowJobs(allCompletedJobsForWorkOrderWithDetails, workOrderId);

            // All external API calls have been made; we can now proceed to insert Completed Workflows
            // into Salesforce if they haven't been imported already.
            Map<String,Boolean> insertedCompletedWorkflowResults = new Map<String,Boolean>();

            for (WorkFlowJob workFlowJob : allCompletedJobsForWorkOrderWithDetails) {
                insertedCompletedWorkflowResults.putAll(insertCompletedWorkFlowIntoSalesforce(workFlowJob, workOrderId));
            }

            List<Boolean> successfulWorkFlows = new List<Boolean>();
            for (Boolean status : insertedCompletedWorkflowResults.values()) {
                if (status) {
                    successfulWorkFlows.add(status);
                }
            }

            // Upload all completed reports into Salesforce
            Integer insertedReports = insertCompletedReportIntoSalesforce(completedFlowJobReportsToInsert, workOrderId);
            results.add(success(successfulWorkFlows.size() + ' Completed Workflows have been imported'));
            results.add(success(insertedReports + ' Completed Reports have been imported'));
            return results;
        }
        catch (Exception e) {
            results.add(error(e.getMessage()));
            return results;
        }
    }

    private static List<WorkFlowJob> getAllWorkFlowJobs() {
        String url = 'https://gateway.flow.librestream.com/jobs/v1/';

        Http http = new Http();
        HttpRequest request = new HttpRequest();

        // Provide the Named Credentials
        request.setEndpoint(url);
        request.setMethod('GET');
        request.setHeader('Authorization', 'Bearer ' + getFlowTokenAsync());
        request.setHeader('Content-Type', 'application/json');

        HttpResponse response = http.send(request);

        if (response.getStatusCode() >= 200 && response.getStatusCode() < 300) {
            String jsonResponse = response.getBody();
            List<WorkFlowJob> workFlowJobs = (List<WorkFlowJob>)JSON.deserialize(jsonResponse, List<WorkFlowJob>.class);
            return workFlowJobs;
         }
         return null;
    }

    private static WorkFlowJob getAllWorkFlowJobsWithDetails(String jobId) {
        String url = 'https://gateway.flow.librestream.com/jobs/v1/bson/' + jobId;

        Http http = new Http();
        HttpRequest request = new HttpRequest();

        // Provide the Named Credentials
        request.setEndpoint(url);
        request.setMethod('GET');
        request.setHeader('Authorization', 'Bearer ' + getFlowTokenAsync());
        request.setHeader('Content-Type', 'application/json');

        HttpResponse response = http.send(request);

        if (response.getStatusCode() >= 200 && response.getStatusCode() < 300) {
            String jsonResponse = response.getBody();
            WorkFlowJob workFlowJob = (WorkFlowJob)JSON.deserialize(jsonResponse, WorkFlowJob.class);
            return workFlowJob;
         }
         return null;
    }

    private static ReportResponse getCompletedReport(String jobId) {
        String url = 'https://gateway.flow.librestream.com/reportgenerator/v1/generate?jobId=' + jobId;

        Http http = new Http();
        HttpRequest request = new HttpRequest();

        // Provide the Named Credentials
        request.setEndpoint(url);
        request.setMethod('POST');
        request.setHeader('Authorization', 'Bearer ' + getFlowTokenAsync());
        request.setHeader('Content-Type', 'application/json');
        request.setHeader('Content-Length', '0');

        HttpResponse response = http.send(request);

        if (response.getStatusCode() >= 200 && response.getStatusCode() < 300) {
            String jsonResponse = response.getBody();
            ReportResponse report = (ReportResponse)JSON.deserialize(jsonResponse, ReportResponse.class);

            return report;
         }

         return null;
    }

    /**
     * @param workFlowJob the completed Workflow Job for the Salesforce Work Order.
     * @param workOrderId Id of the Salesforce WorkOrder associated with this Completed
     * Work Flow. This should be the same Work Order ID recorded as metadata within
     * Onsight Flow. If the Workflow was launched from the Salesforce UI, this
     * metadata tag will have been automatically recorded.
     */
    private static Map<String, Boolean> insertCompletedWorkFlowIntoSalesforce(WorkFlowJob workFlowJob, Id workOrderId) {
        Map<String, Boolean> results = new Map<String,Boolean>();
        Completed_Workflow__c occ = new Completed_Workflow__c();
        occ.ID__c = workFlowJob.jobId;
        occ.Name = workFlowJob.metadata.jobTitle;
        occ.Work_Order__c = workOrderId;
        occ.Client_Job_Id__c = workFlowJob.metadata.clientJobId;
        occ.Created__c = workFlowJob.metadata.created;
        occ.Metadata__c = (String)JSON.serialize(workFlowJob.metadata.metadata);

        occ.Modified__c = workFlowJob.metadata.modified;
        occ.Status__c = workFlowJob.metadata.status;
        occ.Team__c = workFlowJob.team;
        occ.Updated__c = workFlowJob.metadata.updated;
        occ.User_Id__c = workFlowJob.metadata.userId;
        occ.Workflow_Id__c = workFlowJob.metadata.workflowId;
        occ.Workflow_Version_Id__c = workFlowJob.metadata.workflowVersionId;
        occ.Username__c = workFlowJob.metadata.username;
        occ.Workflow_Name__c = workFlowJob.metadata.workflowName;

        try {
            insert occ;

            if (workFlowJob.completedSteps != null) {
                for (CompletedSteps completedStep : workFlowJob.completedSteps) {
                    Onsite_Workflow_Step__c ows = new Onsite_Workflow_Step__c();
                    ows.Completed_Workflow__c = occ.Id;
                    ows.Description__c = completedStep.singleStep.stepDescription;
                    ows.Notes__c = completedStep.singleStep.note;
                    ows.Name = completedStep.singleStep.stepTitle;
                    ows.User__c = completedStep.singleStep.userName;
                    ows.Completed__c = completedStep.singleStep.completed;
                    ows.Started__c = completedStep.singleStep.started;
                    ows.Step_Number__c = completedStep.singleStep.stepNumber;
                    ows.Step_Type__c = completedStep.singleStep.stepType;
                    if (completedStep.singleStep.values.size() != 0) {
                        ows.Input__c = JSON.serialize(completedStep.singleStep.values);
                    }
                    insert ows;
                }
            }
            results.put(occ.ID__C, true);
            return results;
        }
        catch (DmlException e) {
            if (e.getDmlType(0) == StatusCode.DUPLICATE_VALUE) {
                results.put(occ.ID__c, false);
                return results;
            }
            throw e;
        }
    }

    // gets the valid api token for flow using the proxy/shim
    private static string getFlowTokenAsync() {
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

    public class WorkFlowJob {
        @auraEnabled
        public String jobId;
        @auraEnabled
        public Metadata metadata;
        @AuraEnabled
        public List<CompletedSteps> completedSteps;
        @auraEnabled
        public String team;
        @auraEnabled
        public Boolean excluded;
        @auraEnabled
        public String completedReportURL;
    }

    public class CurrentStep {
        @auraEnabled
        public SingleStep singleStep;
        @auraEnabled
        public String reportStep;
    }

    public class CompletedSteps {
        @auraEnabled
        public SingleStep singleStep;
        @auraEnabled
        public String reportStep;
    }

    public class Metadata {
        @auraEnabled
        public String clientJobId;
        @auraEnabled
        public String workflowId;
        @auraEnabled
        public String workflowVersionId;
        @auraEnabled
        public String jobTitle;
        @auraEnabled
        public Map<String,String> metadata;
        @auraEnabled
        public DateTime created;
        @auraEnabled
        public DateTime updated;
        @auraEnabled
        public DateTime modified;
        @auraEnabled
        public String status;
        @auraEnabled
        public String userId;
        @auraEnabled
        public SingleStep currentStep;
        @auraEnabled
        public String username;
        public String workflowName;
    }

    public class SingleStep {
        @auraEnabled
        public String[] values;
        @auraEnabled
        public String[] valueResourceIds;
        @auraEnabled
        public String uniqueStepId;
        @auraEnabled
        public String previousUniqueStepId;
        @auraEnabled
        public String userId;
        @auraEnabled
        public String userName;
        @auraEnabled
        public String deviceId;
        @auraEnabled
        public Integer stepNumber;
        @auraEnabled
        public String stepId;
        @auraEnabled
        public String stepTitle;
        @auraEnabled
        public String stepDescription;
        @auraEnabled
        public String stepType;
        @auraEnabled
        public String connectionType;
        @auraEnabled
        public DateTime started;
        @auraEnabled
        public DateTime completed;
        @auraEnabled
        public DateTime updated;
        @auraEnabled
        public String cancelled;
        @auraEnabled
        public Map<String,Integer> timeEvents;
        @auraEnabled
        public String note;
        @auraEnabled
        public String coordinates;
        @auraEnabled
        public String parentStepId;
        @auraEnabled
        public String parentUniqueStepId;
        @auraEnabled
        public String parentStepTitle;
        @auraEnabled
        public String parentStepDescription;
        @auraEnabled
        public Map<String,String> metadata;
    }

    public class WorkFlow {
        @auraEnabled
        public String workflowId;
        @auraEnabled
        public DateTime created;
        @auraEnabled
        public DateTime lastUpdated;
        @auraEnabled
        public String activeVersionId;
        @auraEnabled
        public String teamName;
        @auraEnabled
        public String name;
        @auraEnabled
        public String description;
        @auraEnabled
        public List<Version> versions;
        @auraEnabled
        public Boolean isArchived;
        @auraEnabled
        public String workflowIdForDraft;
        @auraEnabled
        public String workflowIdForApproval;
        @auraEnabled
        public Boolean approvalsMigrated;
        @auraEnabled
        public String[] liveObjectIds;
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


    public class User {
        public String userId;
        public String username;
        public String emailAddress;
        public String name;
        public DateTime created;
        public Boolean locked;
    }

    public class FlowReport {
        public String blobData;
        public String jobTitle;
        public String workOrderId;
    }

    public class ReportResponse
    {
        public String jobId;
        public String status;
        public String reportUrl;
    }

    /**
     * Helper class to format the API call result string.
     */
    private class ControllerResult {
        String error;
        String success;

        public ControllerResult(String success, String error) {
            this.success = success;
            this.error = error;
        }
    }

    /**
     * Helper which wraps an error message as a JSON string to be returned to the web client.
     */
    private static String error(String message) {
        return (String)JSON.serialize(new ControllerResult(null, message));
    }

    /**
     * Helper which wraps a success message as a JSON string to be returned to the web client.
     */
    private static String success(String message) {
        return (String)JSON.serialize(new ControllerResult(message, null));
    }
}
