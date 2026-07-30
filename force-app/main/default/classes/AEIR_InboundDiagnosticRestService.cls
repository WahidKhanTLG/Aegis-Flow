@RestResource(urlMapping='/aegis-flow/v1/diagnostics/*')
global with sharing class AEIR_InboundDiagnosticRestService {
    private static final Integer MAX_PAYLOAD_CHARS = 100000;
    @HttpPost
    global static void postDiagnostic() {
        RestResponse response = RestContext.response;
        response.addHeader('Content-Type', 'application/json');
        try {
            // Session authentication alone lets any authenticated integration user write
            // arbitrary diagnostics. Capture is an explicitly granted capability (spec 15).
            if (!FeatureManagement.checkPermission('AEIR_Inbound_Diagnostic_Capture')) {
                response.statusCode = 403;
                response.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
                    'success' => false,
                    'message' => 'The Aegis Inbound Diagnostic Capture permission is required.'
                }));
                return;
            }
            String body = RestContext.request.requestBody == null ? null : RestContext.request.requestBody.toString();
            if (String.isBlank(body)) throw new AEIR_RestException('A JSON diagnostic payload is required.');
            // Bound the payload so a malformed or hostile caller cannot push oversized
            // context through masking and into storage.
            if (body.length() > MAX_PAYLOAD_CHARS) {
                throw new AEIR_RestException('Payload exceeds the ' + MAX_PAYLOAD_CHARS + ' character limit.');
            }
            AEIR_ErrorCaptureService.ErrorInput input;
            try {
                input = (AEIR_ErrorCaptureService.ErrorInput)JSON.deserialize(body, AEIR_ErrorCaptureService.ErrorInput.class);
            } catch (Exception parseError) {
                throw new AEIR_RestException('The diagnostic payload is not valid JSON for this contract.');
            }
            if (input == null) throw new AEIR_RestException('A JSON diagnostic payload is required.');
            if (String.isBlank(input.sourceType)) input.sourceType = 'API';
            AEIR_ErrorCaptureService.CaptureResult result = AEIR_ErrorCaptureService.capture(input);
            response.statusCode = result.success == true ? 201 : 400;
            response.responseBody = Blob.valueOf(JSON.serialize(result));
        } catch (Exception ex) {
            response.statusCode = 400;
            response.responseBody = Blob.valueOf(JSON.serialize(new Map<String,Object>{ 'success' => false, 'message' => ex.getMessage() }));
        }
    }
    global class AEIR_RestException extends Exception {}
}