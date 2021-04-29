public with sharing class OnsightConnectController {
    /**
     * Asks the Onsight Connect API to generate a call URI for the given request.
     */
    @AuraEnabled
    public static String getConnectUriAsync(String requestBody) {
        Http http = new Http();
        HttpRequest request = new HttpRequest();
         
        // Provide the Named Credentials
        request.setEndpoint('callout:Onsight_Connect_URI');
        request.setMethod('POST');
        request.setHeader('Authorization', 'ls Bearer: {!$Credential.Password}');
        request.setHeader('Content-Type', 'application/json');
        request.setBody(requestBody);

        HttpResponse response = http.send(request);
        if (response.getStatusCode() >= 200 && response.getStatusCode() < 300) {
            return response.getBody().remove('"');
        }

        return null;
    }
}
