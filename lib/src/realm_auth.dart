part of realm;

class RealmAuth {
  final Realm realm;

  const RealmAuth._(this.realm);

  Future<void> confirmUser(
      String token,
      String tokenId,
      ) async {
    // TODO: Implements
  }

  Future<void> confirmPasswordReset(
      String token,
      String tokenId,
      String password,
      ) async {
    // TODO: Implements
  }

  Future<void> sendPasswordResetEmail(String email) async {
    // TODO: Implements
  }

  Future<void> resendConfirmationEmail(String email) async {
    // TODO: Implements
  }

  createUserWithEmailAndPassword(String email, String password) {
    // TODO: Implements
  }

  Future<RealmUser> signInWithCredential(RealmCredential credential) async {
    final result = await this.realm.http.post(
      'auth/providers/${credential.type}/login',
      data: credential.payload,
    );

    final tokenResult = RealmTokenResult._(result.data);
  }

  signInAnonymously() {
    return signInWithCredential(
      RealmCredential.anonymous(),
    );
  }

  signInWithApiKey(String key) {
    return signInWithCredential(
      RealmCredential.apiKey(key),
    );
  }

  signInWithEmailAndPassword(String email, String password) {
    return signInWithCredential(
      RealmCredential.emailAndPassword(email, password),
    );
  }

  signInWithCustomToken(String token) {
    return signInWithCredential(
      RealmCredential.customToken(token),
    );
  }
}