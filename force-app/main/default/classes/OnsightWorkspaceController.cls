/**
 * "Imports" a specific Onsight Connect call's Workspace documents/assets into Salesforce.
 * 
 * This implementation does not import the actual asset content from Workspace. Instead, it
 * first creates an instance of an OnsightConnectCall custom object, which will serve as the
 * parent of any documents/assets captured during the given Onsight Connect call. This also mimics
 * the document structure within Onsight Workspace, where Call "documents" own child asset documents.
 * 
 * After ensuring that an OnsightConnectCall object exists within Salesforce, each child document/asset
 * in Workspace gets a corresponding OnsightWorkspaceDocument object created in Salesforce, with references back
 * to the underlying Workspace document. Each custom OnsightWorkspaceDocument object is then added to its
 * OnsightConnectCall parent.
 * 
 * At the end, there is 1:1 correspondence between the Onsight Workspace documents
 */
public with sharing class OnsightWorkspaceController {
    public static String WORKSPACE_ROOT_URI = 'https://workspace.librestream.com/onsight/ui/#!/browse/';


    /**
     * Main entry point. Invoked by the Lightning web component when 
     * the user clicks the "Import" button.
     */
    @AuraEnabled
    public static String importAssetsAsync(Id workOrderId) {
        // Search by salesforceWorkOrderId; could add other metadata search criteria as well.
        Map<String, String> searchTerms = new Map<String, String> {
            'salesforceWorkOrderId' => workOrderId
        };

        try {
            // Ask Onsight Workspace to fetch all documents/assets matching the search terms
            List<Document> assets = findDocumentsInWorkspace(searchTerms);

            // Map an Onsight Call document ID to its Salesforce Call object ID
            Map<String, Id> onsightToCallObjId = new Map<String, Id>();
            Map<String, Document> assetToCallMap = new Map<String, Document>();

            // Make all outgoing API calls up-front before we being inserting anything into Salesforce;
            // otherwise, we'll get "you have uncommitted work pending" errors.
            for (Document asset : assets) {
                // Ask Onsight Workspace to fetch the Onsight Call document which owns this Document
                Document parentDoc = getWorkspaceDocument(asset.parentID);

                // Keep track of this Call object, as the next Document might reference it, too
                assetToCallMap.put(asset.parentID, parentDoc);
            }

            // All external API calls have been made; we can now proceed to insert Workspace
            // assets into Salesforce if they haven't been imported already.
            for (Document asset : assets) {
                // Do we already have an OnsightConnectCall object for this Document?
                Id callObjId = onsightToCallObjId.get(asset.parentID);
                String onsightCallName = '';

                // Ask Onsight Workspace to fetch the Onsight Call document which owns this Document
                Document parentDoc = assetToCallMap.get(asset.parentID);

                // Assuming Workspace finds the given Onsight Call document, make sure that
                // we have a corresponding OnsightConnectCall object in Salesforce which
                // references this call.
                if (parentDoc != null) {
                    onsightCallName = parentDoc.title;
                    callObjId = insertCallIntoSalesforce(parentDoc, workOrderId);
                    if (callObjId == null) {
                        return error('Failed to create new OnsightConnectCall object for this WorkOrder');
                    }

                    // Keep track of this Call object, as the next Document might reference it, too
                    onsightToCallObjId.put(asset.parentID, callObjId);
                }

                // Create a corresponding Salesforce object which will *reference* this Onsight Workspace Document
                Id sfDoc = insertCorrespondingSalesforceDocument(onsightCallName, callObjId, asset);
                if (sfDoc == null) {
                    return error('Failed to insert Onsight Workspace asset into Salesforce');
                }
            }

            return success(assets.size() + ' Onsight Connect asset(s) have been imported');
        }
        catch (Exception e) {
            return error(e.getMessage());
        }
    }

    /**
     * Ask Onsight Workspace to fetch the parent Call document with the given ID.
     * 
     * @param documentId the Onsight Workspace document ID of an Onsight Call. This
     * should be a Call or Workspace "folder"-type document ID.
     */
    private static Document getWorkspaceDocument(String documentId) {
        HttpResponse resp = callWorkspace('/' + documentId);
        if (resp.getStatusCode() != 200) {
            return null;
        }

        String jsonResponse = resp.getBody();
        return (Document)JSON.deserialize(jsonResponse, Document.class);
    }

    /**
     * Given an Onsight Workspace call document, try inserting a corresponding
     * OnsightConnectCall custom object into Salesforce. If the OnsightConnectCall
     * with the given callDocument ID already exists, the error is ignored and
     * processing continues normally.
     * 
     * @param callDocument the Onsight Workspace Document of an Onsight Connect call.
     * @param workOrderId Id of the Salesforce WorkOrder associated with this Onsight
     * Connect call. This should be the same Work Order ID recorded as metadata within
     * Onsight Connect. If the Onsight Call was made through the Salesforce UI, this
     * metadata tag will have been automatically recorded.
     */
    private static Id insertCallIntoSalesforce(Document callDocument, Id workOrderId) {
        OnsightConnectCall__c occ = new OnsightConnectCall__c();
        occ.ID__c = callDocument.id;
        occ.Name = callDocument.title;
        occ.Work_Order__c = workOrderId;

        try {
            insert occ;
            return occ.Id;
        }
        catch (DmlException e) {
            // If OnsightConnectCall already exists, return its ID and continue.
            // NOTE: e.getDmlId() is always null, so it's useless. Need to parse the ID from the message string.
            if (e.getDmlType(0) == StatusCode.DUPLICATE_VALUE) {
                return extractDuplicateRecordId(e.getMessage());
            }
            throw e;
        }
    }

    /**
     * Inserts a new OnsightWorkspaceDocument object into Salesforce. This object is merely a
     * reference to a document/asset found in Onsight Workspace, not the Workspace asset itself.
     * 
     * @param callObjId the Salesforce OnsightConnectCall parent object under which the new
     * document will be added.
     * @param wsDoc the Onsight Workspace document/asset for which a reference Salesforce object
     * is to be created.
     */
    private static Id insertCorrespondingSalesforceDocument(String onsightCallName, Id callObjId, Document wsDoc) {
        String onsightDomain = wsDoc.createdBy.substringAfter('@');

        OnsightWorkspaceDocument__c sfDoc = new OnsightWorkspaceDocument__c();
        sfDoc.Name = wsDoc.title;
        sfDoc.ID__c = wsDoc.id;
        sfDoc.Type__c = wsDoc.type;
        sfDoc.Description__c = wsDoc.description;
        sfDoc.External_Metadata__c = (String)JSON.serialize(wsDoc.externalMetadata);
        sfDoc.ParentID__c = wsDoc.parentID;
        sfDoc.Download_URL__c = WORKSPACE_ROOT_URI + onsightDomain + '/workspace/onsight/' + wsDoc.createdBy + '/' + onsightCallName + '/' + wsDoc.title;
        sfDoc.Onsight_Connect_Call__c = callObjId;

        try {
            insert sfDoc;
            return sfDoc.Id;
        }
        catch (DmlException e) {
            // If this is a duplicate record error, quietly return the pre-existing record ID and continue
            if (e.getDmlType(0) == StatusCode.DUPLICATE_VALUE) {
                return extractDuplicateRecordId(e.getMessage());
            }
            throw e;
        }
    }

    /**
     * Call Onsight Workspace to fetch all Workspace Documents matching the given search terms.
     * 
     * @param searchTerms map of metadata names to metadata values to be used as the Workspace search criteria.
     */
    private static List<Document> findDocumentsInWorkspace(Map<String, String> searchTerms) {
        String query = '';
        Integer i = 0;

        // Build the query string of search terms to be passed to Onsight Workspace API
        for (String key : searchTerms.keySet()) {
            String value = searchTerms.get(key);
            if (i++ > 0) {
                query += ' OR ';
            }

            // If value is null/undefined, it means we need to search all metadata fields for the key's value
            if (String.isEmpty(value)) {
                query += '(externalMetadataValue%20=%20%39' + key + '%39)';
            }
            else {
                query += '(externalMetadataName.1%20=%20\'' + key + '\'%20AND%20externalMetadataValue.1%20=%20\'' + value + '\')';
            }
        }

        // Make the Onsight Workspace API call
        HttpResponse resp = callWorkspace('?query=' + query);
        if (resp.getStatusCode() >= 300) {
            return new List<Document>();        // API call failure: return an empty list of Documents
        }

        // Deserialize the JSON response and return the array of Workspace Documents
        String jsonResponse = resp.getBody();
        DocumentList docList = (DocumentList)JSON.deserialize(jsonResponse, DocumentList.class);
        return docList.documents;
    }

    /**
     * Invoke the Onsight Workspace API using the given query string.
     * 
     * @param queryString the query string to be appended to the Onsight Workspace API call.
     */
    private static HttpResponse callWorkspace(String queryString) {
        Http http = new Http();
        HttpRequest request = new HttpRequest();
        
        // Provide the Named Credentials (see: Installation and Configuration instructions)
        request.setEndpoint('callout:Onsight_Workspace_URI' + queryString);
        request.setMethod('GET');
        request.setHeader('X-Api-Key', '{!$Credential.Password}');

        return http.send(request);
        // HttpResponse response = http.send(request);
        // if (response.getStatusCode() == 200) {
        //     return response.getBody();
        // }

        // return '';
    }

    /**
     * Helper which detects a duplicate record ID within a given error message.
     * This allows us to gracefully handle the case of trying to insert the same
     * Salesforce object more than once.
     */
    private static Id extractDuplicateRecordId(String errorMessage) {
        if (String.isEmpty(errorMessage)) {
            return null;
        }

        Pattern p = Pattern.compile('.+record with id\\: (.+)\\:.*');
        Matcher m = p.matcher(errorMessage);
        if (m.matches()) {
            return Id.valueOf(m.group(1));
        }

        return null;
    }

    /**
     * Onsight Workspace API call result object.
     * Definition taken from the Librestream Onsight Workspace API documentation.
     */
    public class Document {
        String id;
        String parentID;
        String title;
        String createdBy;
        String downloadURL;
        String type;
        String description;
        Map<String, String> externalMetadata;
    }

    /**
     * Onsight Workspace API call result object. 
     * Definition taken from the Librestream Onsight Workspace API documentation.
     */
    public class DocumentList {
        String type;
        Integer totalResults;
        Integer pageSize;
        Integer currentPageSize;
        Integer pageIndex;
        Integer numberOfPages;
        List<Document> documents;
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
