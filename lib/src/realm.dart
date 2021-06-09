library realm;

import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:dio/dio.dart';
import 'package:meta/meta.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'realm_auth.dart';
part 'realm_collection.dart';
part 'realm_credential.dart';
part 'realm_exception.dart';
part 'realm_fetcher.dart';
part 'realm_functions.dart';
part 'realm_location.dart';
part 'realm_profile.dart';
part 'realm_token_result.dart';
part 'realm_user.dart';
part 'realm_utils.dart';

const kBaseUrl = "https://stitch.mongodb.com";
const kBasePath = "/api/client/v2.0/";
const kSessionKey = "mongo_session";

class Realm {
  final String id;
  final String db;
  final String service;
  final SharedPreferences storage;
  final Dio http;
  final StreamController<RealmUser> _userCtrl = StreamController.broadcast();
  final StreamController<String> _tokenCtrl = StreamController.broadcast();

  Realm._(
    this.id,
    this.db,
    this.storage,
    this.http, [
    this.service = 'mongodb-atlas',
  ]) {
    loadLocation().catchError(
      (e) => log("$e", name: 'Realm.loadLocation'),
    );
  }

  static Future<Realm> initializeApp({
    @required String id,
    @required String db,
  }) async {
    final storage = await SharedPreferences.getInstance();
    final options = BaseOptions(
      baseUrl: '$kBaseUrl$kBasePath',
      // connectTimeout: 5000,
      // receiveTimeout: 3000,
    );

    final http = Dio(options);

    return Realm._(id, db, storage, http);
  }

  Future<RealmLocation> loadLocation() async {
    final response = await http.get('app/$id/location');

    final json = Map.from(response.data);
    final location = RealmLocation._(json);

    print(json);

    if (location.hostname != null) http.options.baseUrl = location.hostname;

    return location;
  }

  String get graphql => '${this.http.options.baseUrl}' 'app/$id/graphql';

  RealmUser get user {
    if (storage.containsKey(kSessionKey)) {
      final data = Map<String, dynamic>.from(
        jsonDecode(storage.getString(kSessionKey)),
      );

      final valid = data.containsKey('id') &&
          data.containsKey('accessToken') &&
          data.containsKey('refreshToken');

      if (!valid) {
        storage.remove(kSessionKey);
        return null;
      }

      return RealmUser._(this, data);
    }
    return null;
  }

  Stream<RealmUser> get onUserChanged => _userCtrl.stream;

  Stream<String> get onTokenChanged => _tokenCtrl.stream;

  RealmAuth get auth {
    return RealmAuth._(this);
  }

  RealmFetcher get fetcher {
    return RealmFetcher._(this);
  }

  // RealmLocation get location {
  //   return storage.containsKey(kLocationKey)
  //       ? RealmLocation._(jsonDecode(storage.getString(kLocationKey)))
  //       : null;
  // }

  RealmFunctions functions(String name) {
    return RealmFunctions._(name, this);
  }

  RealmCollection collection(String name, {String db}) {
    return RealmCollection._(name, db, this);
  }
}
