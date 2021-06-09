part of realm;

class RealmFetcher {
  final Realm realm;

  const RealmFetcher._(this.realm);

  Future<RealmLocation> getLocation() async {
    try {
      final result = await realm.http.get<Map>('app/${realm.id}/location');

      return RealmLocation._(result.data);
    } catch (e) {
      throw new Exception('Error while getting location');
    }
  }

  Future<RealmProfile> getProfile() async {
    try {
      final result = await realm.http.get<Map>('auth/profile');

      return RealmProfile._(result.data);
    } catch (e) {
      throw new Exception('Error while getting profile');
    }
  }

  Future<String> getAccessToken() async {
    try {
      final result = await realm.http.post<Map>('auth/session');

      return result.data['access_token'];
    } catch (e) {
      throw new Exception('Error while getting session');
    }
  }

  Future<void> signOut() async {
    try {
      await realm.http.delete('auth/session');
    } catch (e) {
      throw new Exception('Error while deleting session');
    }
  }

  Future<Map<String, dynamic>> callFunction(
    String name,
    Map<String, dynamic> data,
  ) async {
    try {
      final result = await realm.http.post<Map>(
        'functions/call',
        data: {
          'arguments': [data],
          'name': name,
        },
      );

      return result.data.cast<String, dynamic>();
    } on DioError catch (e) {
      throw new RealmException._fromDioError(e);
    } catch (e) {
      throw new Exception('Error while calling function($name)');
    }
  }

  Stream<Map<String, dynamic>> callFunctionStreaming(
    String name,
    Map<String, dynamic> data,
  ) async* {
    try {
      final result = await realm.http.post<Map>('functions/$name', data: data);

      // // Binary data
      // List<int> postData = <int>[];
      // await realm.http.post(
      //   'functions/$name',
      //   data: Stream.fromIterable(
      //     postData.map((e) => [e]),
      //   ), //create a Stream<List<int>>
      //   options: Options(
      //     headers: {
      //       Headers.contentLengthHeader: postData.length, // set content-length
      //     },
      //   ),
      // );

      yield result.data.cast<String, dynamic>();
    } catch (e) {
      throw new Exception('Error while calling function($name)');
    }
  }

  Future<RealmTokenResult> signInWithCredential(
    RealmCredential credential,
  ) async {
    try {
      final result = await this.realm.http.post<Map>(
            'auth/providers/${credential.type}/login',
            data: credential.payload,
          );

      return RealmTokenResult._(result.data);
    } catch (e) {
      throw new Exception('Error while signing in user');
    }
  }

  Future<void> confirmUser(
    String token,
    String tokenId,
  ) async {
    try {
      await this.realm.http.post<Map>(
        'auth/providers/local-userpass/confirm',
        data: {
          'token': token,
          'tokenId': tokenId,
        },
      );
    } catch (e) {
      throw new Exception('Error on RealmFetcher.confirmUser');
    }
  }

  Future<void> confirmPasswordReset(
    String token,
    String tokenId,
    String password,
  ) async {
    try {
      await this.realm.http.post<Map>(
        'auth/providers/local-userpass/reset',
        data: {
          'token': token,
          'tokenId': tokenId,
          'password': password,
        },
      );
    } catch (e) {
      throw new Exception('Error on RealmFetcher.confirmPasswordReset');
    }
  }

  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await this.realm.http.post<Map>(
        'auth/providers/local-userpass/reset/send',
        data: {
          'email': email,
        },
      );
    } catch (e) {
      throw new Exception('Error on RealmFetcher.sendPasswordResetEmail');
    }
  }

  Future<void> resendConfirmationEmail(String email) async {
    try {
      await this.realm.http.post<Map>(
        'auth/providers/local-userpass/confirm/send',
        data: {
          'email': email,
        },
      );
    } catch (e) {
      throw new Exception('Error on RealmFetcher.resendConfirmationEmail');
    }
  }

  Future<void> createUserWithEmailAndPassword(
    String email,
    String password,
  ) async {
    try {
      await this.realm.http.post<Map>(
        'auth/providers/local-userpass/register',
        data: {
          'email': email,
          'password': password,
        },
      );
    } catch (e) {
      throw new Exception(
          'Error on RealmFetcher.createUserWithEmailAndPassword');
    }
  }

  Future<void> callResetPasswordFunction(
    String email,
    String password,
    Map<String, dynamic> arguments,
  ) async {
    try {
      await this.realm.http.post<Map>(
        'auth/providers/local-userpass/reset/call',
        data: {
          'email': email,
          'password': password,
          'arguments': arguments,
        },
      );
    } catch (e) {
      throw new Exception('Error RealmFetcher.callResetPasswordFunction');
    }
  }

  Future<Dio> getApiClient() async {
    realm.http.interceptors.clear();
    realm.http.interceptors.add(
      InterceptorsWrapper(
        onRequest: (RequestOptions options) {
          // Do something before request is sent
          options.headers["Authorization"] =
              "Bearer " + this.realm.user.accessToken;
          return options;
        },
        onResponse: (Response response) {
          // Do something with response data
          return response; // continue
        },
        onError: (DioError error) async {
          // Do something with response error
          if (error.response?.statusCode == 401) {
            realm.http.interceptors.requestLock.lock();
            realm.http.interceptors.responseLock.lock();
            RequestOptions options = error.response.request;
            final token = await this.realm.user.refreshAccessToken();
            options.headers["Authorization"] = "Bearer " + token;

            realm.http.interceptors.requestLock.unlock();
            realm.http.interceptors.responseLock.unlock();
            return realm.http.request(options.path, options: options);
          } else {
            await this.realm.user.signOut();
            return error;
          }
        },
      ),
    );

    return realm.http;
  }
}
