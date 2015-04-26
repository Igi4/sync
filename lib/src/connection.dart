part of sync.client;

class ClientRequest {
  final dynamic args;
  final String type;

  ClientRequest(this.type, this.args);

  factory ClientRequest.fromJson(Map data) => new ClientRequest(data['type'], data['args']);

  Map toJson() => {'type': type, 'args': args};
}

class PackedRequest {
  final int id;
  final ClientRequest clientRequest;

  PackedRequest(this.id,this.clientRequest);

  Map toJson() => {'id': id, 'clientRequest': clientRequest.toJson()};

  factory PackedRequest.fromJson(Map data) =>
      new PackedRequest(data['id'], new ClientRequest.fromJson(data['clientRequest']));
}

List<PackedRequest> packedRequestsFromJson(List<Map> json) {
  return json.map((one) => new PackedRequest.fromJson(one)).toList();
}

class FailedRequestException implements Exception {
  const FailedRequestException();
  String toString() => "FailedRequestException";
}

class CancelError implements Exception {
  const CancelError();
  String toString() => "CancelError";
}

class ConnectionError extends Error {
  var event;
  ConnectionError(this.event);
}

class ResponseError extends Error {
  var event;
  ResponseError(this.event);
}

typedef ClientRequest CreateRequest();

/**
 * Representation of connection to server.
 */
class Connection {

  final HttpTransport _transport;
  Timer _timer;
  Duration _delayBetweenRequests;
  WebSocket _ws;

  /**
   * Queue of unprepared [ClientRequest]s.
   * The map entry should contain these keys and values:
   *   'createRequest': [CreateRequest] object
   *   'completer': [Completer] object which returns response for the request
   */
  final Queue<Map> _requestQueue = new Queue<Map>();

  final Set<Map> _periodicRequests = new Set<Map>();

  /**
   * Maps [Request] names to their future responses.
   */
  final Map<int, Completer> _responseMap = new Map<int, Completer>();

  /**
   * Counts sent requests. Serves as unique ID for new requests.
   */
  int requestCount = 0;

  Connection.config(this._transport, this._delayBetweenRequests) {
    this._transport.setHandlers(_prepareRequest, _handleResponse, _handleError);
    _timer = new Timer.periodic(this._delayBetweenRequests, (_) {
      for (var request in _periodicRequests) {
        send(request['createRequest']).then((value) {
          request['controller'].add(value);
        }).catchError((e) {
          request['controller'].addError(e);
        });
      }
    });

    Uri wsUrl = Uri.parse(_transport.url);
    wsUrl = wsUrl.replace(scheme: 'ws');

    _ws = new WebSocket('${wsUrl}ws');

    _ws.onOpen.listen((e) {
      logger.info('WS Connected');
    });

    _ws.onClose.listen((e) {
      logger.info('WS closed');
    });
  }

  WebSocket get ws => _ws;

  List<PackedRequest> _prepareRequest() {
    var request_list = [];

    while (!_requestQueue.isEmpty) {
      var map = _requestQueue.removeFirst();
      var clientRequest = map['createRequest'](); // create the request

      if (clientRequest == null) {
        map['completer'].completeError(new CancelError());
      } else {
        request_list.add(new PackedRequest(requestCount, clientRequest));
        _responseMap[requestCount++] = map['completer'];
      }
    }

    return request_list;
  }

  void _handleResponse(Map responses) {
    for (var responseMap in responses['responses']) {
      var id = responseMap['id'];
      var response = responseMap['response'];

      if (_responseMap.containsKey(id)) {
        _responseMap[id].complete(response);
        _responseMap.remove(id);
      }
    }

    _responseMap.forEach((id, request) => throw new Exception("Request $id was not answered!"));
  }

  void _handleError(error) {
    for (var completer in _responseMap.values) {
      completer.completeError(error);
    }

    _responseMap.clear();
  }

  Future send(CreateRequest createRequest) {
    var completer = new Completer();
    _requestQueue.add({'createRequest': createRequest, 'completer': completer});
    _transport.markDirty();
    return completer.future;
  }

  Stream sendPeriodically(CreateRequest createRequest) {
    var periodicRequest = {'createRequest': createRequest};
    var streamController = new StreamController(onCancel: () => _periodicRequests.remove(periodicRequest));

    periodicRequest['controller'] = streamController;
    _periodicRequests.add(periodicRequest);
    _transport.markDirty();

    return streamController.stream;
  }

  void close() {
    if (_timer != null) _timer.cancel();
  }
}

class HttpTransport {
  dynamic _prepareRequest;
  dynamic _handleResponse;
  dynamic _handleError;

  final _sendHttpRequest;
  final String _url;
  String get url => _url;
  bool _isRunning = false;
  bool scheduled = false;

  HttpTransport(this._sendHttpRequest, this._url, [this._timeout = null]);

  /**
   * Seconds after which request is declared as timed-out. Optional parameter.
   * Use only with HttpRequest factories which support it. (Like the one in http_request.dart)
   */
  int _timeout;
  int get timeout => _timeout;

  setHandlers(prepareRequest, handleResponse, handleError) {
    _prepareRequest = prepareRequest;
    _handleResponse = handleResponse;
    _handleError = handleError;
  }

  /**
   * Notifies [HttpTransport] instance that there are some requests to be sent
   * and attempts to send them immediately. If a HttpRequest is already running,
   * the new requests will be sent in next "iteration" (after response is
   * received + time interval _delayBetweenRequests passes).
   */
  markDirty() {
    if (!scheduled) {
      new Future.delayed(new Duration(milliseconds: 50), (){
        if (!_isRunning) {
          _performRequest();
          scheduled = false;
        } else {
          scheduled = false;
          markDirty();
        }
      });
    }

    scheduled = true;
  }

  void _openRequest() {
    _isRunning = true;
  }

  void _closeRequest() {
    _isRunning = false;
  }

  Future _buildRequest(data) {
    if (null == _timeout) {
      return _sendHttpRequest(
        _url,
        method: 'POST',
        requestHeaders: {'Content-Type': 'application/json'},
        sendData: JSON.encode(data)
      );
    } else {
      return _sendHttpRequest(
        _url,
        method: 'POST',
        requestHeaders: {'Content-Type': 'application/json'},
        sendData: JSON.encode(data),
        timeout: _timeout
      );
    }
  }

  void _performRequest() {
    if (_isRunning) {
      return;
    }

    var data = _prepareRequest();
    if (data.isEmpty) return;

    _openRequest();
    _buildRequest(data).then((xhr) {
      _handleResponse(JSON.decode(xhr.responseText));
      _closeRequest();
    }).catchError((e, s) {
      if (e is ConnectionError) {
        _handleError(e);
      } else {
        logger.shout("error", e, s);
        _handleError(new FailedRequestException());
      }

      _closeRequest();
    });
  }
}

Future<HttpRequest> sendHttpRequest(String url,
    {String method, bool withCredentials, String responseType,
  String mimeType, Map<String, String> requestHeaders, sendData,
  void onProgress(ProgressEvent e), int timeout, Function requestFactory}) {
  var completer = new Completer<HttpRequest>();

  var xhr = new HttpRequest();
  if (null != requestFactory) xhr = requestFactory();
  if (method == null) {
    method = 'GET';
  }
  xhr.open(method, url, async: true);

  if (withCredentials != null) {
    xhr.withCredentials = withCredentials;
  }

  if (responseType != null) {
    xhr.responseType = responseType;
  }

  if (mimeType != null) {
    xhr.overrideMimeType(mimeType);
  }

  if (requestHeaders != null) {
    requestHeaders.forEach((header, value) {
      xhr.setRequestHeader(header, value);
    });
  }

  if (onProgress != null) {
    xhr.onProgress.listen(onProgress);
  }

  if (timeout != null) {
    xhr.timeout = timeout;
    xhr.onTimeout.listen((e) {
      return completer.completeError(new ConnectionError(e));
    });
  }

  xhr.onLoad.listen((e) {
    // Note: file:// URIs have status of 0.
    if ((xhr.status >= 200 && xhr.status < 300) ||
        xhr.status == 0 || xhr.status == 304) {
      completer.complete(xhr);
    } else {
      completer.completeError(new ResponseError(e));
    }
  });

  xhr.onError.listen((e) => completer.completeError(new ConnectionError(e)));

  if (sendData != null) {
    xhr.send(sendData);
  } else {
    xhr.send();
  }

  return completer.future;
}

Connection createHttpConnection(url, Duration delayBetweenRequests, [int timeout = null]) =>
  new Connection.config(new HttpTransport(sendHttpRequest, url, timeout), delayBetweenRequests);