import 'package:sync/server.dart';
import 'package:sync/common.dart';
import 'dart:async';

void main() {
  /**
   * Mongo daemon has to be running at its default port.
   * No authentification is used (/etc/mongodb.conf contains auth=false, which
   * is default value).
   * If authentification would be used:
   * url = 'mongodb://clean:clean@127.0.0.1:27017/clean';
   */

  MongoDatabase mongodb = new MongoDatabase('mongodb://127.0.0.1:27017/clean');
  mongodb.create_collection('persons');
  mongodb.createIndex('persons', {'name': 1}, unique: true);

  Future.wait(mongodb.init).then((_) {

    publish('persons', (_) {
      return mongodb.collection("persons");
    });

    publish('personsOlderThan24Desc', (_) {
      return mongodb.collection("persons").find({"age" : {'\$gt' : 24}}).sort({"age": ASC}).limit(3);
    });

//    PUBLISHER.handleSyncRequest({
//      'action': 'get_data',
//      'collection': 'persons'
//    }).then((data) {
//
//      logger.info(data);
//
//      PUBLISHER.handleSyncRequest({
//        'action': 'get_diff',
//        'collection': 'persons',
//        'version': 2
//      }).then((result) {
//
//        logger.info(result);
//
//        //mongodb.close();
//      });
//
//    }).catchError((e) => logger.warning(e));

    Backend.bind('0.0.0.0', 8080, '/home/igi/dart/sync/example').then((backend) {
      logger.info('Backend started');
    });

  });
}