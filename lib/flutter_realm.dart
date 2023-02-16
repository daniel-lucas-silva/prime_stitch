// @dart=2.18
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';
import 'package:bson/bson.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String kBaseUrl = "https://realm.mongodb.com";
const String kApiUrl = "/api/client/v2.0";

class RealmRouter {
  String hostname;
  final String appId;
  final String api;

  RealmRouter(this.appId, this.hostname, [String? api]) : api = api ?? "";

  String get session => url('/auth/session');
  String get profile => url('/auth/profile');
  String get app => url('/app/$appId');

  String login(
    String provider, [
    bool link = false,
    Map? extraQueryParams,
  ]) {
    var uri = Uri.parse("$app/auth/providers/$provider/login").replace(
      queryParameters: {
        if (link) "link": true,
        if (extraQueryParams != null) ...extraQueryParams,
      },
    );
    return uri.toString();
  }

  String location() => //
      '$app/location';
  String register(String provider) => //
      "$app/auth/providers/$provider/register";
  String confirm(String provider) => //
      "$app/auth/providers/$provider/confirm";
  String confirmSend(String provider) => //
      "$app/auth/providers/$provider/confirm/send";
  String reset(String provider) => //
      "$app/auth/providers/$provider/reset";
  String resetSend(String provider) => //
      "$app/auth/providers/$provider/reset/send";
  String resetCall(String provider) => //
      "$app/auth/providers/$provider/reset/call";
  String functionsCall() => //
      "$app/functions/call";

  String url([String path = '']) => "$hostname$api$path";
}

class RealmService {
  late final Dio client;
  final SharedPreferences prefs;
  final String appId;
  final String dbName;
  final RealmRouter router;

  RealmService._(
    this.appId, {
    required this.dbName,
    RealmRouter? router,
    required this.prefs,
  }) : router = router ?? RealmRouter(appId, kBaseUrl, kApiUrl) {
    hydrate();
    client = Dio()
      ..options.contentType = "application/json"
      ..options.validateStatus = (status) => true;
  }

  String? _accessToken;
  String? _refreshToken;

  static Future<RealmService> initialize(
    String id, {
    required String dbName,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    // TODO(daniel): initialize local storage(sqlite)
    return RealmService._(
      id,
      dbName: dbName,
      prefs: prefs,
    );
  }

  RealmLocation? _location;
  RealmLocation? get location => _location;

  DeviceInformation get deviceInformation => storage.getDeviceInformation();

  Future<void> loadLocation() async {
    try {
      Map value = await fetchJSON("GET", router.location(), tokenType: "none");

      _location = RealmLocation.fromJson(value);

      if (_location!.hostname != null) router.hostname = _location!.hostname!;
    } catch (error, stackTrace) {
      dev.log("$error", error: error, stackTrace: stackTrace, name: "loadLocation");

      _location = null;
    }
  }

  _RealmStorage get storage => _RealmStorage(prefs);

  final List<RealmUser> users = [];

  RealmUser? get currentUser {
    try {
      return users.firstWhere((user) => user.state == RealmUserState.active);
    } catch (e) {
      return null;
    }
  }

  RealmAuth auth() => RealmAuth._(this);

  RealmFunctions functions(String name) => RealmFunctions._(this, name);

  RealmCollection collection(String name, {String? db}) => RealmCollection._(this, name, db ?? dbName);

  RealmUser _createOrUpdateUser(Map<String, dynamic> body) {
    RealmUser? existingUser;

    for (final user in users) {
      if (user.id == body['user_id']) {
        existingUser = user;
        continue;
      }
    }

    if (existingUser != null) {
      // Update the users access and refresh tokens
      existingUser.accessToken = body['access_token'];
      existingUser.refreshToken = body['refresh_token'];
      return existingUser;
    } else {
      // Create and store a new user
      final user = RealmUser._(
        this,
        body['user_id'],
        accessToken: body['access_token'],
        refreshToken: body['refresh_token'],
      );
      users.insert(0, user);
      return user;
    }
  }

  void hydrate() {
    try {
      print("storage.getUserIds() ${storage.getUserIds()}");

      var _users = storage.getUserIds()?.map((id) => RealmUser._(this, id)..hydrate());
      if (_users != null) {
        users
          ..clear()
          ..addAll(_users);
      }
    } catch (err) {
      // The storage was corrupted
      print(err);
      storage.clear();
      rethrow;
    }
  }

  Future<T> fetchJSON<T>(
    String method,
    String url, {
    RealmUser? user,
    String? tokenType,
    Map<String, dynamic>? body,
    Map<String, String>? headers,
    Map<String, String>? queryParameters,
    T Function(dynamic)? decoder,
    dynamic Function(double)? uploadProgress,
  }) async {
    Future<Response> fetch() {
      if (user == null && tokenType == "access") throw Exception();

      return client.fetch(
        RequestOptions(
          path: url,
          data: body,
          method: method,
          queryParameters: queryParameters,
          headers: {
            if (user != null && tokenType == "access") "Authorization": "Bearer ${user.accessToken}",
            if (user != null && tokenType == "refresh") "Authorization": "Bearer ${user.refreshToken}",
            if (headers != null) ...headers,
          },
        ),
      );
    }

    if (user != null) user = currentUser;

    Response res = await fetch();

    if (res.statusCode == 200) {
      return res.data;
    } else if (user != null && res.statusCode == 401 && tokenType == "access") {
      await user.refreshAccessToken();

      res = await fetch();

      if (res.statusCode == 401) {
        await user.signOut();
      } else {
        return res.data;
      }
    }
    throw RealmException.fromRequestAndResponse(res);
  }

  Future<Stream> fetchStream() async {
    throw Exception("Unimplemented fetchStream");
  }

  @visibleForTesting
  Future<T> callFunction<T>(
    String name,
    dynamic args, {
    String? service,
    T Function(dynamic)? decoder,
  }) {
    return fetchJSON<T>(
      "POST",
      router.functionsCall(),
      body: {
        "name": name,
        if (args != null) "arguments": args is List ? args : [args],
        if (service != null) "service": service,
      },
      decoder: decoder,
      tokenType: "access",
      user: currentUser,
    );
  }

  @visibleForTesting
  Future<T> callStream<T>(
    String name,
    dynamic args, {
    String? service,
    Map<String, String> headers = const {},
    Map<String, dynamic> query = const {},
    T Function(dynamic)? decoder,
    dynamic Function(double)? uploadProgress,
  }) async {
    var body = {
      "name": name,
      if (args != null) "arguments": args,
      if (service != null) "service": service,
    };

    var result = await fetchJSON<T>(
      "GET",
      router.functionsCall(),
      headers: {
        ...headers,
        "Authorization": "Bearer $_accessToken",
        "Accept": "text/event-stream",
      },
      queryParameters: {
        ...query,
        "baas_request": base64.encode(utf8.encode(json.encode(body))),
      },
      decoder: decoder,
    );
    return result;
  }
}

class RealmUser {
  final RealmService service;
  final String id;
  String? _accessToken;
  String? _refreshToken;

  RealmUser._(
    this.service,
    this.id, {
    String? accessToken,
    String? refreshToken,
  })  : _accessToken = accessToken,
        _refreshToken = refreshToken {
    hydrate();
  }
  RealmUserState get state {
    if (service.users.any((element) => id == element.id)) {
      return refreshToken == null ? RealmUserState.loggedOut : RealmUserState.active;
    } else {
      return RealmUserState.removed;
    }
  }

  bool get isLoggedIn => state == RealmUserState.active;

  late RealmUserProfile _profile;
  RealmUserProfile get profile => _profile;

  List<RealmUserIdentity>? get identities => _profile.identities;

  String? get accessToken => _accessToken;
  set accessToken(String? token) {
    _accessToken = token;
    service._accessToken = token;
    service.storage.setAccessToken(token);
  }

  String? get refreshToken => _refreshToken;
  set refreshToken(String? token) {
    _refreshToken = token;
    service._refreshToken = token;
    service.storage.setRefreshToken(token);
  }

  DecodedAccessToken? get customData => accessToken != null ? DecodedAccessToken(accessToken!).userData : null;

  Future<void> signOut() async {
    try {
      if (service._refreshToken != null) {
        await service.fetchJSON(
          "DELETE",
          service.router.session,
          tokenType: "refresh",
        );
        service.storage.removeUserId(id);
        service.users.removeWhere((element) => element.id == id);
      }
    } finally {
      accessToken = null;
      refreshToken = null;
    }
  }

  Future<void> linkCredentials(RealmCredential credential) async {
    try {
      var response = await service.fetchJSON(
        'POST',
        service.router.login(credential.providerType),
        body: credential.payload,
      );

      // var user = service._createOrUpdateUser(response);

      if (id != response['user_id']) {
        var details = "got user id ${response['user_id']} expected $id";
        throw Exception("Link response ment for another user ($details)");
      }

      accessToken = response['access_token'];
      await refreshProfile();

      service.storage.setUserIds(
        service.users.map((u) => u.id).toList(),
        true,
      );
    } catch (e, stackTrace) {
      dev.log("$e", name: "RealmAuth.signInWithCredential");
      dev.log("$stackTrace", name: "stackTrace");
      rethrow;
    }
  }

  Future<void> refreshProfile() async {
    try {
      var body = await service.fetchJSON(
        "GET",
        service.router.profile,
        user: this,
      );
      dev.log(body);
      _profile = RealmUserProfile.fromJson(body);
      service.storage.setProfile(_profile);
    } catch (e, stackTrace) {
      dev.log(e.toString());
      dev.log(stackTrace.toString());
    }
  }

  Future<void> refreshAccessToken() async {
    try {
      final response = await service.fetchJSON(
        "POST",
        service.router.session,
        tokenType: "refresh",
      );

      accessToken = response['access_token'];
    } catch (e) {
      rethrow;
    }
  }

  Future<DecodedAccessToken?> refreshCustomData() async {
    await refreshAccessToken();
    return customData;
  }

  hydrate() {
    // Hydrate tokens
    var accessToken = service.storage.getAccessToken();
    var refreshToken = service.storage.getRefreshToken();
    var profile = service.storage.getProfile();
    if (accessToken is String) {
      this.accessToken = accessToken;
    }
    if (refreshToken is String) {
      this.refreshToken = refreshToken;
    }
    _profile = profile!;
  }

  toJson() {
    return {
      "id": id,
      "access_token": accessToken,
      "refresh_token": refreshToken,
      "profile": _profile.toJson(),
      "state": state,
      "custom_data": customData,
    };
  }

  DecodedAccessToken decodeAccessToken() {
    if (accessToken != null) {
      return DecodedAccessToken(accessToken!);
    } else {
      throw Exception("Missing an access token");
    }
  }
}

enum RealmUserState {
  active,
  loggedOut,
  removed,
}

enum RealmUserType {
  normal,
  server,
}

class RealmUserProfile {
  final Map data; // {email}
  final List<RealmUserIdentity>? identities; // {id, provider_id, provider_type}
  final String? domainId; // domain_id
  final String type;
  final String userId; // user_id

  const RealmUserProfile(
    this.data,
    this.identities,
    this.domainId,
    this.type,
    this.userId,
  );

  factory RealmUserProfile.fromJson(Map json) {
    print(json);
    return RealmUserProfile(
      json['data'],
      json['identities'] != null
          ? List.from(json['identities']).map((e) => RealmUserIdentity.fromJson(e)).toList()
          : [],
      json['domain_id'],
      json['type'],
      json['user_id'],
    );
  }

  toJson() {
    return {
      'data': data,
      'identities': identities?.map((e) => e.toJson()).toList(),
      'domain_id': domainId,
      'type': type,
      'user_id': userId,
    };
  }
}

class RealmAuth {
  final RealmService service;

  RealmAuth._(this.service);

  Future<RealmUser> signInWithCredential(RealmCredential credential) async {
    try {
      await service.loadLocation();
      var body = await service.fetchJSON(
        'POST',
        service.router.login(credential.providerType),
        body: credential.payload,
      );

      var user = service._createOrUpdateUser(body);

      switchUser(user);
      await user.refreshProfile();

      service.storage.setUserIds(
        service.users.map((u) => u.id).toList(),
        true,
      );

      var devInfo = await DeviceInformation.load(body["device_id"]);

      if (kDebugMode) {
        dev.log(body);
      }

      service.storage.setDeviceInformation(devInfo);

      return user;
    } catch (error, stackTrace) {
      dev.log(
        "$error",
        name: "RealmAuth.signInWithCredential",
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }

    // response.body["user_id"];
    // response.body["access_token"];
    // response.body["refresh_token"];
    // response.body["device_id"];

    // var data = response.body!;

    // if (data.containsKey('user_id'))
    //   throw Exception("Expected a user id in the response");

    // if (data.containsKey('access_token'))
    //   throw Exception("Expected an access token in the response");

    // await service.storage.set("users.${data["user_id"]}", data);

    // // return { userId, accessToken, refreshToken, deviceId };
    // return RealmUser._(
    //   service,
    //   data["user_id"],
    // )
    //   ..refreshToken = data["refresh_token"]
    //   ..accessToken = data["access_token"];
  }

  void switchUser(RealmUser nextUser) {
    var index = service.users.indexWhere((u) => u == nextUser);
    if (index == -1) {
      throw Exception("The user was never logged into this app");
    }
    // Remove the user from the stack
    // Insert the user in the beginning of the stack
    service.users
      ..removeAt(index)
      ..insert(0, nextUser);
  }

  Future<RealmUser> signInWithCustomToken(String key) {
    return signInWithCredential(RealmCredential.apiKey(key));
  }

  Future<RealmUser> signInWithEmailAndPassword(
    String email,
    String password,
  ) async {
    return await signInWithCredential(
      RealmCredential.emailPassword(email, password),
    );
  }

  Future<RealmUser> signInWithFacebook(String redirectUrlOrAuthCode) {
    return signInWithCredential(
      RealmCredential.google(redirectUrlOrAuthCode),
    );
  }

  Future<RealmUser> signInWithGoogle(String redirectUrlOrAccessToken) {
    return signInWithCredential(
      RealmCredential.facebook(redirectUrlOrAccessToken),
    );
  }

  Future<RealmUser> signInWithApple(String redirectUrlOrIdToken) {
    return signInWithCredential(
      RealmCredential.apple(redirectUrlOrIdToken),
    );
  }

  Future<void> confirmUser(String token, String tokenId) async {
    try {
      await service.fetchJSON<Map>(
        'POST',
        service.router.confirm('local-userpass'),
        body: {"token": token, "tokenId": tokenId},
      );
    } catch (e, stackTrace) {
      dev.log("$stackTrace", name: "RealmAuth.confirmUser");
      rethrow;
    }
  }

  Future<void> createUserWithEmailAndPassword(
    String email,
    String password,
  ) async {
    try {
      await service.fetchJSON<Map>(
        'POST',
        service.router.register('local-userpass'),
        body: {"email": email, "password": password},
      );
    } catch (e, stackTrace) {
      dev.log("$stackTrace", name: "RealmAuth.createUserWithEmailAndPassword");
      rethrow;
    }
  }

  Future<void> resendConfirmationEmail(String email) async {
    try {
      await service.fetchJSON<Map>(
        'POST',
        service.router.confirmSend('local-userpass'),
        body: {"email": email},
      );
    } catch (e, stackTrace) {
      dev.log("$stackTrace", name: "RealmAuth.resendConfirmationEmail");
      rethrow;
    }
  }

  Future<void> resetPassword(
    String token,
    String tokenId,
    String password,
  ) async {
    try {
      await service.fetchJSON<Map>(
        'POST',
        service.router.reset('local-userpass'),
        body: {"token": token, "tokenId": tokenId, "password": password},
      );
    } catch (e, stackTrace) {
      dev.log("$stackTrace", name: "RealmAuth.resetPassword");
      rethrow;
    }
  }

  Future<void> sendResetPasswordEmail(String email) async {
    try {
      await service.fetchJSON<Map>(
        'POST',
        service.router.resetSend('local-userpass'),
        body: {"email": email},
      );
    } catch (e, stackTrace) {
      dev.log("$stackTrace", name: "RealmAuth.sendResetPasswordEmail");
      rethrow;
    }
  }

  Future<void> callResetPasswordFunction(
    String email,
    String password,
    Object arguments,
  ) async {
    try {
      await service.fetchJSON<Map>(
        'POST',
        service.router.resetCall('local-userpass'),
        body: {"email": email, "password": password, "arguments": arguments},
      );
    } catch (e, stackTrace) {
      dev.log("$stackTrace", name: "RealmAuth.sendResetPasswordEmail");
      rethrow;
    }
  }
}

class RealmFunctions {
  final RealmService service;
  final String name;

  const RealmFunctions._(this.service, this.name);
}

class RealmCollection {
  final RealmService service;
  final String collection;
  final String database;

  RealmCollection._(this.service, this.collection, this.database);

  Future<T> query<T>(
    String name, {
    Map? query,
    Map? options,
    T Function(dynamic)? decoder,
  }) async {
    try {
      // {database: "todo", collection: "Task", query: {}, limit: {$numberInt: "10"}}
      var response = await service.callFunction<T>(
        name,
        {
          "database": database,
          "collection": collection,
          "query": query ?? {},
          if (options != null) ...options,
        },
        decoder: decoder,
        service: "mongodb-atlas",
      );

      return response;
    } catch (e, stackTrace) {
      dev.log("$stackTrace", name: "RealmCollection.$name");

      rethrow;
    }
  }

  Future<T> mutation<T>(
    String name, {
    required dynamic payload,
    Map? query,
    Map? options,
  }) async {
    try {
      // {database: "todo", collection: "Task", query: {}, limit: {$numberInt: "10"}}
      var body = {
        "database": database,
        "collection": collection,
        if (query != null) "query": query,
        if (options != null) ...options,
      };

      switch (name) {
        case "updateOne":
        case "updateMany":
        case "findOneAndUpdate":
        case "findOneAndReplace":
          if (payload != null) body["update"] = payload;
          break;
        case "insertOne":
          body["document"] = payload;
          break;
        case "insertMany":
          body["documents"] = payload;
          break;
        case "aggregate":
          body["pipeline"] = payload;
          break;
        default:
          break;
      }

      var response = await service.callFunction<T>(name, body, service: "mongodb-atlas");

      return response;
    } catch (e, stackTrace) {
      dev.log("$stackTrace", name: "RealmCollection.$name");

      rethrow;
    }
  }

  Future<Map> count([Map? filter, Map? options]) {
    return query<Map>("count", query: filter, options: options);
  }

  Future<Map> findOne([Map? filter, Map? options]) {
    return query<Map>(
      "findOne",
      query: filter,
      options: options,
    );
  }

  Future<List> findMany([Map? filter, Map? options]) {
    return query<List>("find", query: filter, options: options);
  }

  insertOne(Map document) {
    try {
      return service.callFunction("insertOne", {});
    } catch (e, stackTrace) {
      dev.log("$stackTrace", name: "RealmCollection.insertOne");
      rethrow;
    }
  }

  insertMany(Map documents) {
    try {
      return service.callFunction("insertMany", {});
    } catch (e, stackTrace) {
      dev.log("$stackTrace", name: "RealmCollection.insertMany");
      rethrow;
    }
  }

  updateOne(Map filter, Map update, [Map? options]) {
    return mutation<List>(
      "updateOne",
      payload: update,
      query: filter,
      options: options,
    );
  }

  updateMany(Map filter, Map update, [Map? options]) {
    return mutation<List>(
      "updateMany",
      payload: update,
      query: filter,
      options: options,
    );
  }

  deleteOne(Map filter) {
    return mutation<List>("deleteOne", query: filter, payload: null);
  }

  deleteMany(Map filter) {
    return mutation<List>("deleteMany", query: filter, payload: null);
  }

  findOneAndDelete(Map filter, [Map? options]) {
    return mutation<List>(
      "findOneAndReplace",
      payload: null,
      query: filter,
      options: options,
    );
  }

  findOneAndReplace(Map filter, Map replacement, [Map? options]) {
    return mutation<List>(
      "findOneAndReplace",
      payload: replacement,
      query: filter,
      options: options,
    );
  }

  findOneAndUpdate(Map filter, Map update, [Map? options]) {
    return mutation<List>(
      "findOneAndUpdate",
      payload: update,
      query: filter,
      options: options,
    );
  }
}

class RealmDocument {
  final RealmCollection collection;
  final RealmData data;

  RealmDocument._(this.collection, Map<String, dynamic> data) : data = RealmData._(data);

  update(Map<String, dynamic> data) {}

  stream() {}
}

class RealmData {
  final Map<String, dynamic> data;

  const RealmData._(this.data);

  child(String fieldPath) {
    var data = get(fieldPath);
    if (data! is Map) throw Exception("Result $fieldPath is not Map type");
    return RealmData._(data);
  }

  get(String fieldPath) {
    return data[fieldPath];
  }

  T map<T, E>(String fieldPath, T Function(E) transform) {
    var data = get(fieldPath);
    return transform(data);
  }
}

class RealmCredential<T> {
  final String providerName;
  // "anon-user" | "api-key" | "local-userpass" | "custom-function" | "custom-token" | "oauth2-google" | "oauth2-facebook" | "oauth2-apple"
  final String providerType;
  final Map<String, dynamic> payload;

  RealmCredential(this.providerName, this.providerType, this.payload);

  static RealmCredential<dynamic> anonymous() {
    return RealmCredential("anon-user", "anon-user", {});
  }

  static RealmCredential<dynamic> userApiKey(String key) {
    return RealmCredential("api-key", "api-key", {"key": key});
  }

  static RealmCredential<dynamic> serverApiKey(String key) {
    return RealmCredential("api-key", "api-key", {"key": key});
  }

  static RealmCredential<dynamic> apiKey(String key) {
    return RealmCredential("api-key", "api-key", {"key": key});
  }

  static RealmCredential<dynamic> emailPassword(String email, String password) {
    return RealmCredential("local-userpass", "local-userpass", {
      "username": email,
      "password": password,
    });
  }

  static RealmCredential<dynamic> function(Map<String, dynamic> payload) {
    return RealmCredential("custom-function", "custom-function", payload);
  }

  static RealmCredential<dynamic> jwt(String token) {
    return RealmCredential("custom-token", "custom-token", {"token": token});
  }

  static RealmCredential<dynamic> google(String redirectUrlOrAuthCode) {
    return RealmCredential("oauth2-google", "oauth2-google", {
      if (redirectUrlOrAuthCode.contains("://"))
        "redirectUrl": redirectUrlOrAuthCode
      else
        "authCode": redirectUrlOrAuthCode,
    });
  }

  static RealmCredential<dynamic> facebook(String redirectUrlOrAccessToken) {
    return RealmCredential(
      "oauth2-facebook",
      "oauth2-facebook",
      {
        if (redirectUrlOrAccessToken.contains("://"))
          "redirectUrl": redirectUrlOrAccessToken
        else
          "accessToken": redirectUrlOrAccessToken
      },
    );
  }

  static RealmCredential<dynamic> apple(String redirectUrlOrIdToken) {
    return RealmCredential(
      "oauth2-apple",
      "oauth2-apple",
      {
        if (redirectUrlOrIdToken.contains("://"))
          "redirectUrl": redirectUrlOrIdToken
        else
          "id_token": redirectUrlOrIdToken
      },
    );
  }
}

class RealmException implements Exception {
  late String message;
  final String method;
  final Uri url;
  final int statusCode;
  final String? statusText;
  final String? error;
  final String? errorCode;
  final String? link;

  RealmException._(
    this.method,
    this.url,
    this.statusCode,
    this.statusText,
    this.error,
    this.errorCode,
    this.link,
  ) {
    var summary =
        statusText != null || statusText!.isNotEmpty ? "status $statusCode $statusText" : "status $statusCode";

    message = "Request failed ($method $url): $error ($summary)";
  }

  static RealmException fromRequestAndResponse(Response res) {
    Map body = res.data;

    var error = body.containsKey('error') ? body['error'] : "No message";
    var errorCode = body['error_code'];
    var link = body['link'];

    return RealmException._(
      res.requestOptions.method,
      res.requestOptions.uri,
      res.statusCode!,
      res.statusMessage,
      error,
      errorCode,
      link,
    );
  }
}

class _RealmStorage {
  final SharedPreferences preferences;

  _RealmStorage(this.preferences);

  List<String>? getUserIds() {
    return preferences.getStringList('userIds');
  }

  Future<void> setUserIds(List<String> userIds, bool mergeWithExisting) async {
    if (mergeWithExisting) {
      final existingIds = getUserIds() ?? [];

      for (final id in existingIds) {
        if (!userIds.contains(id)) userIds.add(id);
      }
    }

    await preferences.setStringList('userIds', userIds);
  }

  Future<void> removeUserId(String userId) async {
    final existingIds = getUserIds() ?? [];
    final userIds = existingIds.where((id) => id != userId).toList();
    await preferences.setStringList('userIds', userIds);
  }

  Future<void> setDeviceInformation(DeviceInformation devInfo) async {
    await preferences.setString('deviceInformation', json.encode(devInfo.toJson()));
  }

  DeviceInformation getDeviceInformation() {
    final value = preferences.getString('deviceInformation');
    if (value != null) {
      return DeviceInformation.fromJson(json.decode(value));
    }
    return DeviceInformation('', '', '', '', '');
  }

  Future<void> setDeviceId(String deviceId) async {
    await preferences.setString('deviceId', deviceId);
  }

  String? getAccessToken() {
    return preferences.getString('accessToken');
  }

  Future<void> setAccessToken(String? accessToken) async {
    if (accessToken != null) {
      await preferences.setString('accessToken', accessToken);
    } else {
      await preferences.remove('accessToken');
    }
  }

  String? getRefreshToken() {
    return preferences.getString('refreshToken');
  }

  Future<void> setRefreshToken(String? refreshToken) async {
    if (refreshToken != null) {
      await preferences.setString('refreshToken', refreshToken);
    } else {
      await preferences.remove('refreshToken');
    }
  }

  RealmUserProfile? getProfile() {
    final value = preferences.getString('profile');
    if (value != null) {
      return RealmUserProfile.fromJson(json.decode(value));
    }
    return null;
  }

  Future<void> setProfile(RealmUserProfile? profile) async {
    if (profile != null) {
      await preferences.setString('profile', json.encode(profile.toJson()));
    } else {
      await preferences.remove('profile');
    }
  }

  T? get<T>(String key) {
    final value = preferences.getString(key);
    if (value != null) {
      return json.decode(value) as T;
    }
    return null;
  }

  Future<void> set(String key, dynamic value) async {
    await preferences.setString(key, json.encode(value));
  }

  Future<void> remove(String key) async {
    await preferences.remove(key);
  }

  Future<void> clear() async {
    await preferences.clear();
  }
}

class RealmUserIdentity {
  final String id;
  final String providerId;
  final String providerType;
  final Map<String, dynamic> providerData;

  const RealmUserIdentity(
    this.id,
    this.providerId,
    this.providerType,
    this.providerData,
  );

  factory RealmUserIdentity.fromJson(Map json) {
    dev.log(json.toString());
    return RealmUserIdentity(
      json['id'],
      json['provider_id'],
      json['provider_type'],
      Map.from(json['provider_data']),
    );
  }

  toJson() {
    return {
      "id": id,
      "provider_id": providerId,
      "provider_type": providerType,
      "provider_data": providerData,
    };
  }
}

class RealmLocation {
  const RealmLocation(
    this.deploymentModel,
    this.location,
    this.hostname,
    this.wsHostname,
  );

  final String? deploymentModel;
  final String? location;
  final String? hostname;
  final String? wsHostname;

  factory RealmLocation.fromJson(Map data) {
    return RealmLocation(
      data.containsKey("deployment_model") ? data["deployment_model"] : null,
      data.containsKey("location") ? data["location"] : null,
      data.containsKey("hostname") ? data["hostname"] : null,
      data.containsKey("ws_hostname") ? data["ws_hostname"] : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      "deployment_model": deploymentModel,
      "location": location,
      "hostname": hostname,
      "ws_hostname": wsHostname,
    };
  }
}

class DeviceInformation {
  final String? appName;
  final String? appVersion;
  final String? deviceId;
  final String? platform;
  final String? platformVersion;

  const DeviceInformation(
    this.appName,
    this.appVersion,
    this.deviceId,
    this.platform,
    this.platformVersion,
  );

  static Future<DeviceInformation> load(String deviceId) async {
    var deviceInfo = DeviceInfoPlugin();
    // String? deviceId;
    String? appName;
    String? appVersion;
    String? platform;
    String? platformVersion;

    if (kIsWeb) {
      var webBrowserInfo = await deviceInfo.webBrowserInfo;
      appName = webBrowserInfo.appName;
      appVersion = webBrowserInfo.appVersion;
      deviceId = ObjectId().$oid;
      platform = webBrowserInfo.platform;
    } else if (Platform.isIOS) {
      var data = await deviceInfo.iosInfo;
      appName = data.name;
      appVersion = data.systemVersion;
      // deviceId = data.identifierForVendor;
      platform = data.systemName;
      platformVersion = data.systemVersion;
    } else if (Platform.isAndroid) {
      var build = await deviceInfo.androidInfo;
      appName = build.model;
      appVersion = build.version.toString();
      // deviceId = build.androidId;
      platform = build.version.codename;
      platformVersion = build.version.release;
    }

    return DeviceInformation(
      appName,
      appVersion,
      deviceId,
      platform,
      platformVersion,
    );
  }

  factory DeviceInformation.fromJson(Map json) {
    return DeviceInformation(
      json['app_name'],
      json['app_version'],
      json['device_id'],
      json['platform'],
      json['platform_version'],
    );
  }

  toJson() {
    return {
      "app_name": appName,
      "app_version": appVersion,
      "device_id": deviceId,
      "platform": platform,
      "platform_version": platformVersion,
    };
  }
}

class DecodedAccessToken {
  final dynamic expires;
  final dynamic issuedAt;
  final dynamic subject;
  final dynamic userData;

  const DecodedAccessToken._(
    this.expires,
    this.issuedAt,
    this.subject,
    this.userData,
  );

  factory DecodedAccessToken(String accessToken) {
    final parts = accessToken.split(".");

    if (parts.length != 3) {
      throw Exception("Expected an access token with three parts");
    }
    // Decode the payload
    var encodedPayload = parts[1];
    var decodedPayload = utf8.decode(base64.decode(encodedPayload));
    var parsedPayload = json.decode(decodedPayload);

    return DecodedAccessToken._(
      parsedPayload["exp"],
      parsedPayload["iat"],
      parsedPayload["sub"],
      parsedPayload["user_data"],
    );
  }
}
