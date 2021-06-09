part of realm;

class RealmCollection {
  final String name;
  final String db;
  final Realm realm;

  const RealmCollection._(this.name, this.db, this.realm);

  find(
    Map<String, dynamic> filter, {
    int limit,
  }) {}

  findOne(
    Map<String, dynamic> filter,
  ) {}

  findOneAndUpdate(
    Map<String, dynamic> filter,
    Map<String, dynamic> update, {
    bool upsert,
    bool returnNewDocument,
  }) {}

  findOneAndReplace(
    Map<String, dynamic> filter,
    Map<String, dynamic> replacement, {
    bool upsert,
    bool returnNewDocument,
  }) {}

  findOneAndDelete(
    Map<String, dynamic> filter, {
    Map<String, dynamic> sort,
    Map<String, dynamic> projection,
  }) {}

  aggregate({
    Map<String, dynamic> pipeline,
  }) {}

  count(
    Map<String, dynamic> filter, {
    int limit,
  }) {}

  insertOne(
    Map<String, dynamic> document,
  ) {}

  insertMany(
    List<Map<String, dynamic>> document,
  ) {}

  deleteOne(
    Map<String, dynamic> filter,
  ) {}

  deleteMany(
    Map<String, dynamic> filter,
  ) {}

  updateOne(
    Map<String, dynamic> filter,
    Map<String, dynamic> update, {
    bool upsert,
  }) {}

  updateMany(
    Map<String, dynamic> filter,
    Map<String, dynamic> update, {
    bool upsert,
  }) {}

  watch({
    List<String> ids,
    Map<String, dynamic> filter,
  }) {}
}

class RealmDocument {
  final String id;
  final Map<String, dynamic> data;

  const RealmDocument._(this.id, this.data);

  update() {}

  delete() {}

  watch() {}
}
