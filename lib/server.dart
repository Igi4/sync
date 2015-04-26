/**
 * A library for data subscription and synchronization in single page
 * applications.
 */

library sync.server;

import 'dart:async';
import 'package:mongo_dart/mongo_dart.dart';
import 'dart:math';
import 'dart:convert';
import "package:sync/common.dart";
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_static/shelf_static.dart';
import 'package:shelf_route/shelf_route.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';

part 'src/publisher.dart';
part 'src/data_provider.dart';
part 'src/mongo_provider.dart';
part 'src/backend.dart';