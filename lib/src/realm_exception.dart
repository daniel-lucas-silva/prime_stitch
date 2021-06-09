part of realm;

class RealmException implements Exception {
  final String method;
  final String url;
  final int statusCode;
  final String statusText;
  final String error;
  final String errorCode;
  final String link;

  const RealmException._(
    this.method,
    this.url,
    this.statusCode,
    this.statusText, [
    this.error,
    this.errorCode,
    this.link,
  ]);

  factory RealmException._fromDioError(DioError e) {
    final url = e.request.uri.toString();
    final method = e.request.method;
    final statusCode = e.response.statusCode;
    final statusMessage = e.response.statusMessage;
    final contentType = e.response.headers.value('content-type');
    if (contentType != null && contentType.startsWith('application/json')) {
      final body = Map.from(e.response.data);
      return RealmException._(
        method,
        url,
        statusCode,
        statusMessage,
        body.find('error', 'No message'),
        body.find('error_code', ''),
        body.find<String>('link'),
      );
    } else {
      return RealmException._(
        method,
        url,
        statusCode,
        statusMessage,
      );
    }
  }
}
