import 'dart:developer' as dev;
import 'dart:io';

import 'package:flutter/foundation.dart';

/// On HarmonyOS, Dart stdout is silently dropped — it never reaches `flutter attach`
/// or DevTools. This logger writes to a file so you can stream it with:
///   bash dev.sh --log
///
/// The file path is hardcoded to the OHOS app sandbox data dir (no path_provider needed).
const String _ohosLogPath = '/data/storage/el2/base/haps/entry/files/debug.log';

IOSink? _sink;

Future<void> initDevLogger() async {
  if (!kDebugMode) return;
  try {
    final file = File(_ohosLogPath);
    await file.parent.create(recursive: true);
    // Truncate on each app start so log doesn't grow unbounded.
    _sink = file.openWrite(mode: FileMode.writeOnly);
    log('=== DevLogger started ===');
  } catch (e) {
    // Not on OHOS or permission denied — fall back gracefully.
    debugPrint('[DevLogger] could not open log file: $e');
  }
}

void log(String message, {String name = 'app'}) {
  if (!kDebugMode) return;
  final ts = DateTime.now().toIso8601String().substring(11, 23); // HH:mm:ss.mmm
  final line = '$ts [$name] $message';
  // dart:developer -> DevTools Logging tab (works if DevTools is connected)
  dev.log(message, name: name);
  // file -> streamable via `hdc shell tail -f /data/storage/el2/base/haps/entry/files/debug.log`
  _sink?.writeln(line);
}

Future<void> flushDevLogger() async => _sink?.flush();
