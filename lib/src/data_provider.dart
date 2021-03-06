part of sync.server;

abstract class DataProvider {
  /** Returns collection of items in the following form:
   * {'data': [List<Map>] data, 'version': [num] version_num}
   */
  Future<Map> data();
  /** Returns collection of items in the following form:
   *  {'diff': [List<Map>]} or
   *  {'diff': null, 'data': [List<Map>] data, 'version': [num] version_num}
   *
   *  If 'diff' value is not null, items in the list are of following form:
   *  {'action': 'add'/'change',
   *   '_id': 'value0',
   *   'author': 'Some String',
   *   'data': {'_id': 'value0', 'field1': 'value1', 'field2': 'value2', ...}
   *   'version': 5}
   *
   *  or
   *
   *  {'action': 'remove',
   *   '_id': 'value0',
   *   'author': 'Some String',
   *   'version': 5}
   *
   *  In case of 'add', value of 'data' is a [Map] representing new data that
   *  was added. In case of 'change', value of 'data' is a [Map] containing new
   *  key-value pairs and/or pairs of already existing keys and updated values.
   */
  Future<Map> diffFromVersion(num version, {Map highestElement: null, num collectionLength : 0});
  Future add(Map data, String author);
  Future change(String id, Map change, String author);
  Future remove(String id, String author);
  String fullName();
}
