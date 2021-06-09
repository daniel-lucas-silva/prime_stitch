part of realm;

class RealmProfile {
  final String type;
  final List<Map> identities;
  final Map data;

  RealmProfile._(Map json)
      : type = json.find<String>('type'),
        identities = json.find<List>('identities', []).cast<Map>(),
        data = json.find<Map>('data');

  @override
  String toString() => jsonEncode({
        'type': type,
        'identities': identities,
        'data': data,
      });
}
