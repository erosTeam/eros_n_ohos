import 'dart:developer' as dev;
import 'dart:io';

import 'package:flutter/foundation.dart';

/// On HarmonyOS, Dart stdout is silently dropped — it never reaches `flutter attach`
/// or DevTools. This logger writes to a file so you can stream it with:
///   bash dev.sh --log
///
/// The file path is hardcoded to the OHOS app sandbox data dir (no path_provider needed).
const String _ohosLogPath = '/data/storage/el2/base/haps/entry/files/debug.log';

File? _logFile;

Future<void> initDevLogger() async {
  if (!kDebugMode) return;
  try {
    final file = File(_ohosLogPath);
    await file.parent.create(recursive: true);
    // Truncate on each app start so log doesn't grow unbounded.
    file.writeAsStringSync('', mode: FileMode.writeOnly, flush: true);
    _logFile = file;
    log('=== DevLogger started ===');
  } catch (e) {
    // Not on OHOS or permission denied — fall back gracefully.
    debugPrint('[DevLogger] could not open log file: $e');
  }
}

void _appendLine(String line) {
  final f = _logFile;
  if (f == null) return;
  try {
    f.writeAsStringSync('$line\n',
        mode: FileMode.writeOnlyAppend, flush: true);
  } catch (e) {
    // Swallow — logging failure must not break the app.
    debugPrint('[DevLogger] write failed: $e');
  }
}

void log(String message, {String name = 'app'}) {
  if (!kDebugMode) return;
  final ts = DateTime.now().toIso8601String().substring(11, 23); // HH:mm:ss.mmm
  final line = '$ts [$name] $message';
  // dart:developer -> DevTools Logging tab (works if DevTools is connected)
  dev.log(message, name: name);
  _appendLine(line);
}

/// Write multiple lines as a single log entry. Used by the `logger` package
/// bridge so that pretty-printed multi-line output stays grouped.
/// No-op when the sink isn't open (e.g. on non-OHOS platforms).
void writeLines(Iterable<String> lines, {String name = 'app'}) {
  if (!kDebugMode || _logFile == null) return;
  final ts = DateTime.now().toIso8601String().substring(11, 23);
  final buf = StringBuffer();
  for (final line in lines) {
    buf
      ..write(ts)
      ..write(' [')
      ..write(name)
      ..write('] ')
      ..writeln(line);
  }
  try {
    _logFile!.writeAsStringSync(buf.toString(),
        mode: FileMode.writeOnlyAppend, flush: true);
  } catch (e) {
    debugPrint('[DevLogger] writeLines failed: $e');
  }
}

Future<void> flushDevLogger() async {
  // No-op now that every write is synchronous + flushed.
}
