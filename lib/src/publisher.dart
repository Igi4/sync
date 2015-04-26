part of sync.server;

typedef Future<DataProvider> DataGenerator(Map args);
typedef void CollectionSetter(String collection);
typedef void CollectionNotifier(String collection);

final int MAX = pow(2,16) - 1;
final int prefix_random_part = new Random().nextInt(MAX);

class Resource {
  DataGenerator generator;

  Future handleSyncRequest(Map data, CollectionSetter setCollection, CollectionNotifier notify) {
    var action = data["action"];
    var reqVersion = data['version'];
    var highestElement = data['highestElement'];
    var collectionLength = data['collectionLength'] != null ? data['collectionLength'] : 0;

    return new Future.value(generator(data['args']))
      .then((DataProvider dp) {
        setCollection(dp.fullName());

        if (action == "get_data") {
          return dp.data();
        }
        else if(action == "get_diff") {
          return dp.diffFromVersion(reqVersion, highestElement: highestElement, collectionLength: collectionLength);
        }
        else if (action == "add") {
          return dp.add(data['data'], data['author']).then((result) {
            notify(dp.fullName());
            return result;
          });
        }
        else if (action == "change") {
          return dp.change(data['_id'], data['change'], data['author']).then((result) {
            notify(dp.fullName());
            return result;
          });
        }
        else if (action == "remove") {
          return dp.remove(data['_id'], data['author']).then((result) {
            notify(dp.fullName());
            return result;
          });
        }
      });
  }

  Resource(this.generator);
}

class Publisher {
  int counter = 0;

  Map<String, Resource> _resources = {};
  Map<String, String> _resourceToCollection = {};
  Map<String, Set<String>> _collectionToResources = {};
  Map<String, Set> _clients = {};
  Map<dynamic, Set<String>> _ws = {};
  Future notification = new Future.value(null);

  void publish(String collection, DataGenerator generator) {
    _resources[collection] = new Resource(generator);
  }

  bool isPublished(String collection) {
    return _resources.containsKey(collection);
  }

  Set clients(String collection) {
    if (_clients.containsKey(collection)) {
      return _clients[collection];
    }

    return new Set();
  }

  void registerClient(ws, resource) {
    if (_resourceToCollection.containsKey(resource)) {
      if (!_clients.containsKey(_resourceToCollection[resource])) {
        _clients[_resourceToCollection[resource]] = new Set();
      }

      _clients[_resourceToCollection[resource]].add(ws);

      if (!_ws.containsKey(ws)) {
        _ws[ws] = new Set();
      }

      _ws[ws].add(_resourceToCollection[resource]);
    }
  }

  void unregisterClient(ws) {
    if (_ws.containsKey(ws)) {
      _ws[ws].forEach((collection) {
        _clients[collection].remove(ws);
      });

      _ws.remove(ws);
    }
  }

  void notifyClients(clients, collections) {
    Completer completer = new Completer();

    notification.then((_) {
      notification = completer.future;
      new Timer(new Duration(milliseconds: 1), () {
        String msg = JSON.encode(collections);

        clients.forEach((client) {
          client.add(msg);
        });

        completer.complete(null);
      });
    });
  }

  Future handleSyncRequest(Map data) {
    if(data['args'] == null) {
      data['args'] = {};
    }

    var action = data["action"];

    if (action == "get_id_prefix") {
      return new Future(getIdPrefix).then((prefix) => {'id_prefix': prefix});
    }

    Resource resource = _resources[data['collection']];

    return resource.handleSyncRequest(data, (String collection) {
      _resourceToCollection[data['collection']] = collection;

      if (!_collectionToResources.containsKey(collection)) {
        _collectionToResources[collection] = new Set();
      }

      _collectionToResources[collection].add(data['collection']);
    }, (String collection) {
      notifyClients(clients(collection), _collectionToResources.containsKey(collection) ? _collectionToResources[collection].toList() : []);
    }).catchError((e) {
        logger.shout('handle sync request error:', e);

        return new Future.value({
          'error': e.toString(),
        });
      });
  }

  String getIdPrefix() {
    String prefix =
        new DateTime.now().millisecondsSinceEpoch.toRadixString(36) +
        prefix_random_part.toRadixString(36) + counter.toRadixString(36);
    counter = (counter + 1) % MAX;
    return prefix;
  }
}

final PUBLISHER = new Publisher();

void publish(String c, DataGenerator dg) {
  PUBLISHER.publish(c, dg);
}

//bool isPublished(String collection) {
//  return PUBLISHER.isPublished(collection);
//}
//
Future handleSyncRequest(request) {
  return PUBLISHER.handleSyncRequest(request);
}

void registerClient(ws, resource) {
  PUBLISHER.registerClient(ws, resource);
}

void unregisterClient(ws) {
  PUBLISHER.unregisterClient(ws);
}

//
//String getIdPrefix() {
//  return PUBLISHER.getIdPrefix();
//}
