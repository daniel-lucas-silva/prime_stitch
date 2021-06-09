part of realm;

class RealmTokenResult {
  final String access_token;
  final String device_id;
  final String refresh_token;
  final String user_id;

  RealmTokenResult._(Map json)
      : access_token = json.find<String>('access_token'),
        device_id = json.find<String>('device_id'),
        refresh_token = json.find<String>('refresh_token'),
        user_id = json.find<String>('user_id');

  @override
  String toString() => jsonEncode({
    'access_token': access_token,
    'device_id': device_id,
    'refresh_token': refresh_token,
    'user_id': user_id,
  });
}