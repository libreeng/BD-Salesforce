public with sharing class OnsightWorkspaceController {

    @AuraEnabled
    public static String importAssetsAsync(Id workOrderId) {
        // Search by salesforceWorkOrderId; could add other metadata search criteria as well.
        Map<String, String> searchTerms = new Map<String, String> {
            'salesforceWorkOrderId' => workOrderId
        };

        try {
            List<Document> assets = findDocumentsInWorkspace(searchTerms);

            // Map an Onsight Call document ID to its Salesforce Call object ID
            Map<String, Id> onsightToCallObjId = new Map<String, Id>();

            for (Document asset : assets) {
                Id callObjId = onsightToCallObjId.get(asset.parentID);

                // Insert parent OnsightConnectCall if not already done so
                if (callObjId == null) {
                    Document parentDoc = getWorkspaceDocument(asset.parentID);
                    if (parentDoc != null) {
                        callObjId = insertCallIntoSalesforce(parentDoc, workOrderId);
                        if (callObjId == null) {
                            return error('Failed to create new OnsightConnectCall object for this WorkOrder');
                        }

                        onsightToCallObjId.put(asset.parentID, callObjId);
                    }
                }

                Id sfDoc = insertDocumentIntoSalesforce(callObjId, asset);
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

    private static Document getWorkspaceDocument(String documentId) {
        String jsonResponse = callWorkspace('/' + documentId);
        if (String.isEmpty(jsonResponse)) {
            return null;
        }

        return (Document)JSON.deserialize(jsonResponse, Document.class);
    }

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

    private static Id insertDocumentIntoSalesforce(Id callObjId, Document wsDoc) {
        OnsightWorkspaceDocument__c sfDoc = new OnsightWorkspaceDocument__c();
        sfDoc.Name = wsDoc.title;
        sfDoc.ID__c = wsDoc.id;
        sfDoc.Type__c = wsDoc.type;
        sfDoc.Description__c = wsDoc.description;
        sfDoc.External_Metadata__c = (String)JSON.serialize(wsDoc.externalMetadata);
        sfDoc.ParentID__c = wsDoc.parentID;
        sfDoc.Download_URL__c = wsDoc.downloadUrl;
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

    private static List<Document> findDocumentsInWorkspace(Map<String, String> searchTerms) {
        String query = '';
        Integer i = 0;

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

        String jsonResponse = callWorkspace('?query=' + query);
        if (String.isEmpty(jsonResponse)) {
            return new List<Document>();
        }

        DocumentList docList = (DocumentList)JSON.deserialize(jsonResponse, DocumentList.class);
        return docList.documents;
    }

    private static String callWorkspace(String queryString) {
        Http http = new Http();
        HttpRequest request = new HttpRequest();
        
        // Provide the Named Credentials
        request.setEndpoint('callout:Onsight_Workspace_URI' + queryString);
        request.setMethod('GET');
        request.setHeader('X-Api-Key', '{!$Credential.Password}');

        HttpResponse response = http.send(request);
        if (response.getStatusCode() == 200) {
            return response.getBody();
        }

        return '';
    }

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
     * Definition taken from the Librestream Onsight Workspace API documentation.
     */
    public class Document {
        String id;
        String parentID;
        String title;
        String downloadURL;
        String type;
        String description;
        Map<String, String> externalMetadata;
    }

    /**
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

    private static String error(String message) {
        return (String)JSON.serialize(new ControllerResult(null, message));
    }

    private static String success(String message) {
        return (String)JSON.serialize(new ControllerResult(message, null));
    }



    ///
    /// Experimental: importing Workspace assets as Salesforce files/content.
    ///
    // TODO: can't create external file links without a configured External Data Source.
    // Don't think we can use Workspace as an External Data Source as I think it needs to
    // support certain Salesforce or other APIs/standards for interoperability.
    //
    // So, for now, may need to keep the custom object OnsightWorkspaceDocument for linked assets.
    //
    // @AuraEnabled
    // public static Boolean linkExternalAsset(String assetUrl, String title, Id onsightConnectCallId) {
    //     ContentVersion cv = new ContentVersion();
    //     cv.ContentLocation = 'E';
    //     cv.Title = title;
    //     cv.ContentUrl = assetUrl;
    //     cv.ExternalDataSourceId = 'be29e766-537f-47fd-9bc5-4af9b1c1a52f';

    //     insert cv;
    //     return linkContentToCall(cv, onsightConnectCallId);
    // }

    // // TODO: there's a 50MB limit on uploads. How to work around that?
    // @AuraEnabled
    // public static Boolean importExternalAsset(String title, Id onsightConnectCallId) {
    //     ContentVersion cv = new ContentVersion();
    //     cv.ContentLocation = 'S';
    //     cv.Title = title;
    //     cv.PathOnClient = title;
    //     cv.VersionData = EncodingUtil.base64Decode('iVBORw0KGgoAAAANSUhEUgAAAd0AAABACAMAAABobF11AAABgFBMVEX15+Xrvbfuzsnhemz47u336unkn5Xvy8bhY1Lhg3fprKTuxsHidmjgWUjgYVDibV737ezhfG7pr6fgZVTgYlHgXErjfnHgaFnd5O62xtyLpcn+/v7wt7Hl6/L3+Ptjirr33drAzuDK1eV+ncShttLu8vZxlL/ojILT3OniZVaWrs799/asvtf55uTywbz77u3sopv0ysfmgHT9/f3ql4/kc2b21NHurabgWEb8/Pz47evgZlb7+/voqKD47ezheWvgX07hf3Lgalry1tL58fDw1tPuycXgZFPhfnHlpJzw0c336efgb2HhjID36ejhXk304N70393z3tvstq/gYE/jgHPiZlXv0Mz57+7jlIngg3f+/f3hhXntwbzosqr46effalvptq/psKj48O/ffXH14+H35uPmpp7jjYLhgXTuyMPfc2Xkj4T7+fjlo5rxzcjifXDnqKDffG/gaVrialv17ez37u3mpZziiX3x08/hjoPpqqLz19NVgbXgV0X///9LswutAAAJKklEQVR42uyb95/bRBbAl0BIyOVCSzhJtiSrucle2+stCQlwECDAHfWOznG9917X86+f5Cma8kZ9P3DcvF9Wq+aZ99WbV2bmYNdRkJEvrxwYuoauoWvoGjF0jRi6RgxdI4auoWvoGrqGrqFrxNA1YugaMXSNGLqGrqH7laf79vVPHv3Rv37yeHu6STB3zjNx5kEiXAjsTDzpbjc/6RY3BPBLuUueDd02LV6+v0ER/MThUJTTJfeO0/zMSHpxur9NOLU6PJ7kCpgcD5diR7S/u29XGDt+ppjIoR1uoLhAD9ILF050fu47c+69IN0Pfv/be1t0587B59fb0bX2DaTiWNwVfEa63ylO4hss8K3cJXt/LPdWuUGR/TW1F7P1ir4D/5+KLx7KfR1N+MePNnxHICEdSmL+5DhsqjhLZ0zwe0G6t74zQIP95Sc+bkHXi+W+LaRGylja0j13e6KbyZCnu5uU0k3X8tOTtA7dQD7teM0Up6Ebat4Lj8xfv7ZFg0wQGjx3uyldL1I7F3kiXQlLa7pjrze6uzVPl8GG6KZH6tNHaTXdWD3vJ40UB9O1dc9poqrbT23Jk9vfNKUL9jCW6IpYWtM9n/dHd3coXBzp6U6gp48q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');

    //     insert cv;
    //     return linkContentToCall(cv, onsightConnectCallId);
    // }

    // private static Boolean linkContentToCall(ContentVersion cv, Id onsightConnectCallId) {
    //     ContentDocumentLink cdl = new ContentDocumentLink();
    //     cdl.ContentDocumentId = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id =: cv.Id].ContentDocumentId;
    //     cdl.LinkedEntityId = onsightConnectCallId;
    //     cdl.ShareType = 'I';
    //     insert cdl;

    //     return true;
    // }
}
