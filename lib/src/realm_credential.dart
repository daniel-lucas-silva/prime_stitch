part of realm;

class RealmCredential {
  final String name;
  final String type;
  final Map<String, dynamic> payload;

  const RealmCredential(this.name, this.type, this.payload);

  RealmCredential.customToken(String token)
      : name = 'custom-token',
        type = 'custom-token',
        payload = {'token': token};

  RealmCredential.apiKey(String key)
      : name = 'api-key',
        type = 'api-key',
        payload = {'key': key};

  RealmCredential.anonymous()
      : name = 'anon-user',
        type = 'anon-user',
        payload = {};

  RealmCredential.emailAndPassword(String email, String password)
      : name = 'local-userpass',
        type = 'local-userpass',
        payload = {'username': email, 'password': password};
}
