part of realm;

class RealmLocation {
  final String deployment_model;
  final String hostname;
  final String location;
  final String ws_hostname;

  RealmLocation._(Map json)
      : deployment_model = json.find<String>('deployment_model'),
        hostname = json.find<String>('hostname'),
        location = json.find<String>('location'),
        ws_hostname = json.find<String>('ws_hostname');

  @override
  String toString() => jsonEncode({
        'deployment_model': deployment_model,
        'hostname': hostname,
        'location': location,
        'ws_hostname': ws_hostname,
      });
}
