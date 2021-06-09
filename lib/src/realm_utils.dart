part of realm;

Map<String, dynamic> decodeAccessToken(String accessToken) {
  if (accessToken != null) {
    // Decode and spread the token
    final parts = accessToken.split(".");
    if (parts.length != 3) {
      throw new Exception("Expected an access token with three parts");
    }
    String _decodeBase64(String str) {
      String output = str.replaceAll('-', '+').replaceAll('_', '/');

      switch (output.length % 4) {
        case 0:
          break;
        case 2:
          output += '==';
          break;
        case 3:
          output += '=';
          break;
        default:
          throw Exception('Illegal base64url string!"');
      }

      return utf8.decode(base64Url.decode(output));
    }

    final payload = _decodeBase64(parts[1]);
    final payloadMap = json.decode(payload);
    if (payloadMap is! Map<String, dynamic>) {
      throw Exception('invalid payload');
    }

    return Map<String, dynamic>.from(payloadMap);
  } else {
    throw new Exception("Missing an access token");
  }
}

extension MapExtension<K, V> on Map<K, V> {
  T convert<T>(String path, T Function(Map json) serialize) {
    final data = this.find("$path");

    return serialize(Map.from(data ?? {}));
  }

  E find<E>(String path, [E or]) {
    final List<String> keys = path.split(".");

    if (this == null) return or;

    if (keys.length == 1)
      return this.containsKey(path) ? this[path] ?? or : or ?? null;

    dynamic result = this;

    keys.reduce((prev, curr) {
      if (result is Map &&
          result.containsKey(prev) &&
          result[prev] is Map &&
          result[prev].containsKey(curr)) {
        result = result[prev][curr];
      } else if (result is Map && result.containsKey(curr)) {
        result = result[curr];
      } else {
        result = or ?? null;
      }
      return curr;
    });

    if (or != null && or.runtimeType != result.runtimeType) return or;

    return result ?? or ?? null;
  }
}
