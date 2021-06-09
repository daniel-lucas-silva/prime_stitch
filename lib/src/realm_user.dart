part of realm;

class RealmUser {
  final Realm realm;
  final Map<String, dynamic> data;

  String get id => data.find('id');

  String get providerType => data.find<String>('providerType');

  String get refreshToken => data.find<String>('refreshToken');

  String get accessToken => data.find<String>('accessToken');

  RealmProfile get profile => data.convert('profile', (e) => RealmProfile._(e));

  Map get customData {
    if (this.accessToken != null) {
      final decodedToken = decodeAccessToken(this.accessToken);
      return decodedToken.find('userData');
    } else {
      throw new Exception("Cannot read custom data without an access token");
    }
  }

  RealmUser._(this.realm, this.data);

  Future<String> refreshAccessToken() {
    // get access token passing refreshToken in headers
    // update local accessToken
    // return accessToken
  }

  refreshProfile() {}

  Future<void> signOut() async {
    await this.realm.http.delete('auth/session');
    await this.realm.storage.remove(kSessionKey);
  }
}
