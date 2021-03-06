part of sync.server;

class ModifierException implements Exception {
  final error;
  final stackTrace;
  ModifierException(this.error, this.stackTrace);
  String toString() => "Modifier Error: $error \n Stack trace: $stackTrace";
}

class DiffNotPossibleException implements Exception {
   final String msg;
   const DiffNotPossibleException([this.msg]);
   String toString() => msg == null ? 'DiffNotPossible' : msg;
}

class MongoException implements Exception {
   final mongoError;
   final String msg;
   final String stackTrace;
   const MongoException(this.mongoError, this.stackTrace, [this.msg]);
   String toString() =>
       msg == null ? 'MongoError: $mongoError \n Stack trace: $stackTrace' : '$msg MongoError: $mongoError \n Stack trace: $stackTrace';
}

const String QUERY = "\$query";
const String GT = "\$gt";
const String LT = "\$lt";
const String GTE = "\$gte";
const String LTE = "\$lte";
const String NE = "\$ne";
const String ORDERBY = "\$orderby";
const String OR = "\$or";
const String AND = "\$and";
const String SET = "\$set";
const String UNSET = "\$unset";
const String PUSH = "\$push";
const num ASC = 1;
const num DESC = -1;
const num NOLIMIT = 0;
const num NOSKIP = 0;

const String VERSION_FIELD_NAME = '__clean_version';
const String LOCK_COLLECTION_NAME = '__clean_lock';
final Function historyCollectionName =
  (collectionName) => "__clean_${collectionName}_history";


class MongoDatabase {
  Db _db;
  Future _conn;
  List<Future> init = [];
  DbCollection _lock;

  Db get rawDb => _db;

  MongoDatabase(String url) {
    _db = new Db(url);
    _conn = _db.open(); // open connection to database
    init.add(_conn);
    init.add(_conn.then((_) {
      _lock = _db.collection(LOCK_COLLECTION_NAME);
      return true;
    }));
  }

  void close() {
    Future.wait(init).then((_) => _db.close());
  }

  void create_collection(String collectionName) {
    init.add(_conn.then((_) =>
      _db.createIndex(historyCollectionName(collectionName), key: 'version', unique: true)
    ));
  }

  /**
   * Creates index on chosen collection and corresponding indexes on collection
   * history. keys is a map in form {field_name: 1 or -1} with 1/-1 specifying
   * ascending/descending order (same as the map passed to mongo function
   * ensureIndex).
   */
  void createIndex(String collectionName, Map keys, {unique: false}) {
    Map beforeKeys = {};
    Map afterKeys = {};
    keys.forEach((key, val) {
      beforeKeys['before.$key'] = val;
      afterKeys['after.$key'] = val;
    });
    beforeKeys['version'] = 1;
    afterKeys['version'] = 1;
    init.add(_conn.then((_) =>
        _db.createIndex(historyCollectionName(collectionName),
            keys: beforeKeys)));
    init.add(_conn.then((_) =>
        _db.createIndex(historyCollectionName(collectionName),
            keys: afterKeys)));
    if (keys.isNotEmpty) {
      init.add(_conn.then((_) =>
          _db.createIndex(collectionName, keys: keys, unique: unique)));
    }
  }

  MongoProvider collection(String collectionName) {
    DbCollection collection = _db.collection(collectionName);
    DbCollection collectionHistory =
        _db.collection(historyCollectionName(collectionName));
    return new MongoProvider(collection, collectionHistory, _lock);
  }

  Future dropCollection(String collectionName) =>
    _conn.then((_) => Future.wait([
      _db.collection(collectionName).drop(),
      _db.collection(historyCollectionName(collectionName)).drop()
    ]));

  Future removeLocks() => _lock.drop();
}

List addFieldIfNotEmpty(List fields, String field){
  if (fields.isNotEmpty) {
    var res = new List.from(fields)..add(field);
    return res;
  } else {
    return fields;
  }
}

MongoProvider mpClone(MongoProvider source){
  MongoProvider m = new MongoProvider(source.collection, source._collectionHistory,
      source._lock);
  m._selectorList = new List.from(source._selectorList);
  m._sortParams = new Map.from(source._sortParams);
  m._limit = source._limit;
  m._fields = new List.from(source._fields);
  m._excludeFields = new List.from(source._excludeFields);
  return m;
}

class MongoProvider implements DataProvider {
  final DbCollection collection, _collectionHistory, _lock;
  List<Map> _selectorList = [];
  Map _sortParams = {};
  List _excludeFields = [];
  List _fields = [];
  num _limit = NOLIMIT;

  //for testing purposes
  Future<int> get maxVersion => _maxVersion;

  Future<int> get _maxVersion =>
      _collectionHistory.find(where.sortBy('version', descending : true)
          .limit(1)).toList()
      .then((data) => data.isEmpty? 0: data.first['version']);

  Map get _rawSelector {
    Map sp;

    if (_sortParams.isNotEmpty) {
      sp = new Map.from(_sortParams);
      sp.remove('_id');
      sp['_id'] = ASC;
    }
    else {
      sp = {};
    }

    return {QUERY: _selectorList.isEmpty ? {} : {AND: _selectorList}, ORDERBY: sp};
  }

  MongoProvider(this.collection, this._collectionHistory, this._lock);

  String fullName() => collection.fullName();

  Future deleteHistory(num version) {
    return _collectionHistory.remove({'version': {LT: version}});
  }

  MongoProvider fields(List<String> fields) {
    var res = mpClone(this);
    res._fields.addAll(fields);
    return res;
  }

  MongoProvider excludeFields(List<String> excludeFields) {
    var res = mpClone(this);
    res._excludeFields.addAll(excludeFields);
    return res;
  }

  MongoProvider find([Map params = const {}]) {
    var res = mpClone(this);
    res._selectorList.add(params);
    return res;
  }

  MongoProvider sort(Map params) {
    var res = mpClone(this);
    res._sortParams.addAll(params);
    return res;
  }

  MongoProvider limit(num value) {
    var res = mpClone(this);
    res._limit = value;
    return res;
  }

  String get repr{
    return '${collection.collectionName}$_selectorList$_sortParams$_limit$_fields$_excludeFields';
  }

  /**
   * Returns key-value pairs according to the specified selectors.
   * There should be exactly one entry with specified selectors, otherwise
   * findOne throws an [Exception].
   */
  Future<Map> findOne() {
    return data().then((Map result) {
      List data = result["data"];

      if (data.isEmpty) {
        throw new Exception("There are no entries in database.");
      } else if (data.length > 1) {
        throw new Exception("There are multiple entries in database.");
      }

      return new Future.value(data[0]);
    });
  }

  Future<Map> data({stripVersion: true}) {
    return _data(stripVersion: stripVersion);
  }

  createSelector(Map selector, List fields, List excludeFields) {
    var sel = new SelectorBuilder().raw(selector);
    if (fields.isNotEmpty) {
      sel.fields(fields);
    }
    if (excludeFields.isNotEmpty) {
      sel.excludeFields(excludeFields);
    }
    return sel;
  }

  /**
   * Returns data and version of this data.
   */
  Future<Map> _data({stripVersion: true}) {
    var __fields = addFieldIfNotEmpty(_fields, VERSION_FIELD_NAME);
    SelectorBuilder selector = createSelector(_rawSelector, __fields, _excludeFields)
                               .limit(_limit);
    return collection.find(selector).toList().then((data) {
      var version = data.length == 0 ? 0 : data.map((item) => item['__clean_version']).reduce(max);
      if(stripVersion) _stripCleanVersion(data);
      assert(version != null);
      return {
        'data': data,
        'version': version,
        'limit': _limit,
        'sortParams': _sortParams
      };
    });
  }

  Future writeOperation(String _id, String author, String action, Map newData) {
    num nextVersion;
    return _get_locks()
      .then((_) => collection.findOne({"_id" : _id}))
      .then((Map oldData) {

        if (oldData == null) oldData = {};
        // check that current db state is consistent with required action
        var inferredAction;
        if (oldData.isNotEmpty && newData.isEmpty) inferredAction = 'remove';
        else if (oldData.isEmpty && newData.isNotEmpty) inferredAction = 'add';
        else if (oldData.isNotEmpty && newData.isNotEmpty) inferredAction = 'change';
        else throw true;

        if (action != inferredAction) {
          throw true;
        }

        if (!newData.isEmpty && newData['_id'] != _id) {
          throw new MongoException(null,null,
              'New document id ${newData['_id']} should be same as old one $_id.');
        } else {
          return _maxVersion.then((version) {
            nextVersion = version + 1;
            if (inferredAction == 'remove' ){
              return collection.remove({'_id': _id});
            } else {
              newData[VERSION_FIELD_NAME] = nextVersion;
              if (inferredAction == 'add') {
                return collection.insert(newData);
              } else {
                return collection.save(newData);
              }
            }
          }).then((_) =>
            _collectionHistory.insert({
              "before" : oldData,
              "after" : newData,
              "action" : inferredAction,
              "author" : author,
              "version" : nextVersion
            }));
        }
      }).then((_) => _release_locks()).then((_) => nextVersion)
      .catchError((e) => _release_locks().then((_) {
        if (e is! Exception){
          return e;
        } else {
          throw e;
        }
      }));
  }

  Future change(String _id, Map newData, String author) {
    return writeOperation(_id, author, 'change', newData);
  }

  Future add(Map data, String author) {
    return writeOperation(data['_id'], author, 'add', data);
  }

  Future remove(String _id, String author) {
    return writeOperation(_id, author, 'remove', {});
  }

  Future<Map> diffFromVersion(num version, {Map highestElement: null, num collectionLength : 0}) {
    return _maxVersion.then((maxVer) {
        if (maxVer == version) {
          return {'diff': []};
        }

        return _diffFromVersion(version, highestElement, collectionLength);
      });
  }

  Future<Map> _diffFromVersion(num version, Map highestElement, num collectionLength) {
    return __diffFromVersion(version, highestElement, collectionLength).then((d) {
      return {'diff': d};
    }).catchError((e) {
      if (e is DiffNotPossibleException) {
        return data().then((d) {
          d['diff'] = null;
          return d;
        });
      }
      else {
        throw e;
      }
    });
  }

  List _prettify(List diff){
    Set seen = new Set();
    var res = [];
    for (Map change in diff.reversed) {
      if (change['_id'] is! String) {
        throw new Exception('prettify: found ID that is not String ${change}');
      }
      var id = change['_id']+change['action'];
      assert(id is String);
      if (!seen.contains(id)) {
        res.add(change);
      }
      seen.add(id);
    }
    return new List.from(res.reversed);
  }

  /// in some case not covered so far throws DiffNotPossibleException
  Future<List> __diffFromVersion(num version, Map highestElement, num collectionLength) {
    // selects records that fulfilled _selector before change
    Map beforeSelector = {QUERY : {}, ORDERBY : {"version" : 1}};
    // selects records that fulfill _selector after change
    Map afterSelector = {QUERY : {}, ORDERBY : {"version" : 1}};
    // selects records that fulfill _selector before or after change
    Map beforeOrAfterSelector = {QUERY : {}, ORDERBY : {"version" : 1}};

    // {before: {GT: {}}} to handle selectors like {before.age: null}
    List<Map> _beforeSelector = [{"version" : {GT : version}}, {"before" : {GT: {}}}];
    List<Map> _afterSelector = [{"version" : {GT : version}}, {"after" : {GT: {}}}];
    _selectorList.forEach((item) {
      Map itemB = {};
      Map itemA = {};
      item.forEach((key, val) {
        itemB["before.${key}"] = val;
        itemA["after.${key}"] = val;
      });
      _beforeSelector.add(itemB);
      _afterSelector.add(itemA);
    });
    beforeSelector[QUERY][AND] = _beforeSelector;
    afterSelector[QUERY][AND] = _afterSelector;
    beforeOrAfterSelector[QUERY][OR] = [{AND: _beforeSelector},
                                        {AND: _afterSelector}];

    beforeOrAfterSelector[QUERY]['version'] = {GT: version};

    Set before, after;
    List beforeOrAfter, diff;
    // if someone wants to select field X this means, we need to select before.X
    // and after.X, also we need everythoing from the top level (version, _id,
    // author, action
    List beforeOrAfterFields = [], beforeOrAfterExcludedFields = [];
    for (String field in addFieldIfNotEmpty(this._fields, '_id')){
      beforeOrAfterFields.add('before.$field');
      beforeOrAfterFields.add('after.$field');
    }
    for (String field in this._excludeFields){
      beforeOrAfterExcludedFields.add('before.$field');
      beforeOrAfterExcludedFields.add('after.$field');
    }
    if (beforeOrAfterFields.isNotEmpty) {
      beforeOrAfterFields.addAll(['version', '_id', 'author', 'action']);
    }
        return _collectionHistory.find(createSelector(beforeOrAfterSelector,
                           beforeOrAfterFields, beforeOrAfterExcludedFields)).toList()
        .then((result) {
          beforeOrAfter = result;
          if (beforeOrAfter.isEmpty){
            throw [];
          } else
          return Future.wait([
            _collectionHistory.find(createSelector(beforeSelector, ['_id'], [])).toList(),
            _collectionHistory.find(createSelector(afterSelector, ['_id'], [])).toList()]);})
        .then((results) {
            before = new Set.from(results[0].map((d) => d['_id']));
            after = new Set.from(results[1].map((d) => d['_id']));
            diff = [];

            beforeOrAfter.forEach((record) {
              assert(record['version']>version);

              _stripCleanVersion(record['before']);
              _stripCleanVersion(record['after']);

              if(before.contains(record['_id']) && after.contains(record['_id']))
              {
                // record was changed
                diff.add({
                  "action" : "change",
                  "_id" : record["before"]["_id"],
                  "before" : record["before"],
                  "after": record["after"],
                  "data" : record["after"],
                  "version" : record["version"],
                  "author" : record["author"],
                });
              } else if(before.contains(record['_id'])) {
                // record was removed
                diff.add({
                  "action" : "remove",
                  "_id" : record["before"]["_id"],
                  "before" : record["before"],
                  "data" : record["before"],
                  "version" : record["version"],
                  "author" : record["author"],
                });
              } else {
                // record was added
                diff.add({
                  "action" : "add",
                  "_id" : record["after"]["_id"],
                  "data" : record["after"],
                  "after": record["after"],
                  "version" : record["version"],
                  "author" : record["author"],
                });
              }
            });

            if (_limit > NOLIMIT) {
              return _limitedDiffFromVersion(version, diff, highestElement, collectionLength);
            }

            return _prettify(diff);
    }).catchError((e){
     if (e is List) {
       return e;
     } else {
       throw e;
     }
    });
  }

  Future<List<Map>> _limitedDiffFromVersion(num version, List<Map> beforeOrAfter, Map pivot, num collectionLength) {
    bool beforeLeqPivot(change) {
      return MongoComparator.compareWithKeySelector(change["before"], pivot, _sortParams) < 1;
    }

    bool afterLeqPivot(change) {
      return MongoComparator.compareWithKeySelector(change["after"], pivot, _sortParams) < 1;
    }

    Map add(record) {
      return {
        "action" : "add",
        "_id" : record["after"]["_id"],
        "data" : record["after"],
        "version" : record["version"],
        "author" : record["author"],
      };
    }

    Map change(record) {
      return {
        "action" : "change",
        "_id" : record["before"]["_id"],
        "before" : record["before"],
        "data" : record["after"],
        "version" : record["version"],
        "author" : record["author"],
      };
    }

    Map remove(record) {
      return {
        "action" : "remove",
        "_id" : record["before"]["_id"],
        "data" : record["before"],
        "version" : record["version"],
        "author" : record["author"],
      };
    }

    Map gtRawSelector() {
      Map selector = new Map.from(_rawSelector);
      List<Map> selectorList = new List<Map>.from(_selectorList);
      List<Map> compareSelector = [];
      Map gt;
      String op;
      Map sp = new Map.from(_sortParams);

      sp.remove('_id');
      sp['_id'] = ASC;

      valueForNestedKey(String key) {
        return key.split('.').fold(pivot, (m, k) => m[k]);
      }

      sp.forEach((key, order) {
        gt = {};
        op = (order == ASC) ? GT : LT;
        gt[key] = {op: valueForNestedKey(key)};

        for (String k in sp.keys) {
          if (k == key) break;
          gt[k] = valueForNestedKey(k);
        }

        compareSelector.add(gt);
      });

      selectorList.add({OR: compareSelector});
      selector[QUERY] = {AND : selectorList};

      return selector;
    }

    void printDiff(List diff, num length) {
      print("");
      print("Diff (calculated collection length = $length):");
      diff.forEach((e) => print(e));
      print("");
    }

    if (pivot == null) {
      logger.finer("Limited diff not possible: unknown highest element. Falling back to all data.");
      throw new DiffNotPossibleException();
    }

    logger.info("PIVOT: ${pivot}");

    List diff = [];

    beforeOrAfter.forEach((record) {
      version = record["version"];
      if (record["action"] == "add") {
        if (afterLeqPivot(record)) {
          collectionLength++;
          diff.add(add(record));
        }
        else {
          print("Ignore (add): $record");
        }
      }
      else if (record["action"] == "remove") {
        if (beforeLeqPivot(record)) {
          collectionLength--;
          diff.add(remove(record));
        }
        else {
          print("Ignore (remove): $record");
        }
      }
      else if (record["action"] == "change") {
        if (beforeLeqPivot(record) && afterLeqPivot(record)) {
          diff.add(change(record));
        }
        else if (beforeLeqPivot(record)) {
          collectionLength--;
          diff.add(remove(record));
        }
        else if (afterLeqPivot(record)) {
          collectionLength++;
          diff.add(add(record));
        }
      }
    });

    collectionLength = max(collectionLength, 0);

    if (collectionLength < _limit) {
      print("GT SELECTOR: ${gtRawSelector()}");

      return collection
        .find(where.raw(gtRawSelector()).limit(_limit - collectionLength))
        .toList()
        .then((data) {
          _stripCleanVersion(data);
          data.forEach((element) {
            logger.info("DOPLNENIE: ${element}");
            diff.add({
              "action" : "add",
              "_id" : element["_id"],
              "data" : element,
              "version" : version,
              "author" : "__clean",
            });
          });

          printDiff(diff, collectionLength);

          return diff;
        });
    }
    else {
      printDiff(diff, collectionLength);

      return new Future.value(diff);
    }
  }

  Future _get_locks() {
    return _lock.insert({'_id': collection.collectionName}).then(
      (_) => _lock.insert({'_id': _collectionHistory.collectionName}),
      onError: (e) {
        if(e['code'] == 11000) {
          // duplicate key error index
          return _get_locks();
        } else {
          throw(e);
        }
      }).then((_) => true);
  }

  Future _release_locks() {
    return _lock.remove({'_id': _collectionHistory.collectionName}).then((_) =>
    _lock.remove({'_id': collection.collectionName})).then((_) =>
    true);
  }

  void _stripCleanVersion(dynamic data) {
    if (data is Iterable) {
      data.forEach((Map item) {
        item.remove('__clean_version');
      });
    } else {
      data.remove('__clean_version');
    }
  }
}


