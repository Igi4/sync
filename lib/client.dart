/**
 * A library for data subscription and synchronization in single page
 * applications.
 */

library sync.client;

import "dart:core";
import 'dart:async';
import 'dart:math';
import 'dart:html';
import 'dart:collection';
import "dart:convert";
import "package:clean_data/clean_data.dart";
import "package:sync/common.dart";

part 'src/subscription.dart';
part 'src/subscriber.dart';
part 'src/id_generator.dart';
part 'src/connection.dart';