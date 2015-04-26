part of sync.server;

class Backend {

  static Future bind(address, port, staticPath) {
    var staticHandler = createStaticHandler(staticPath, serveFilesOutsidePath: true, defaultDocument:'index.html');

    Future<shelf.Response> resourceHandler(shelf.Request request) {
      return request.readAsString().then((body) {
        List requests = JSON.decode(body);
        Map response = {'responses': []};

        return Future.forEach(requests, (request) {
          return handleSyncRequest(request['clientRequest']['args']).then((resp) {
            response['responses'].add({
              'id': request['id'],
              'response': resp
            });

            return true;
          });
        }).then((_) {
          logger.info('RESPONSE: ${response}');
          return new shelf.Response.ok(JSON.encode(response));
        }).catchError((e, s) {
          return new shelf.Response.internalServerError(body: 'error: ${e}\n${s}');
        });
      });
    }

    var wsHandler = webSocketHandler((ws) {
      ws.listen((resource) {
        registerClient(ws, resource);
      }, onDone: () {
        unregisterClient(ws);
      });
    });

    var routes = router()
        ..post('/resources/', resourceHandler)
        ..add('/static/*', ['GET'], staticHandler, exactMatch: false)
        ..get('/resources/ws', wsHandler);

    return io.serve(routes.handler, address, port);
  }
}