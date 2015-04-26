# sync
Sync is open-source library that provides efficient real-time data synchronization between client and server. The library is written in Dart language. It uses ```shelf``` as transport layer (HTTP protocol combined with websockets) and utilizes ```clean_data``` for local data collections.

Communication protocol between client and server is based on *publish - subscribe model*. Server publishes data views which clients can subscribe to. After client has subscribed to a data view published by the server, _sync library_ automagically synchronizes the clientside view with changes on the server utilizing efficient communication with the server.

Server-side, the library relies on MongoDB as persistent storage, however, other database solutions can be easily integrated with the _sync library_. Example of publishing a data view on the server's side:
```
publish('personsOlderThan24Desc', (_) {
  return mongodb.collection("persons").find({"age" : {'\$gt' : 24}}).sort({"age": DESC}).limit(10);
});
```
Example of the code for creating a subscribtion to the view:
```
Subscription subscription = subscriber.subscribe("personsOlderThan24Desc");
```
Please see the example for more information and details.


