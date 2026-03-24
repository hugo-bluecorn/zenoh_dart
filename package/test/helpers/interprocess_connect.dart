import 'dart:io';

import 'package:zenoh/zenoh.dart';

/// Helper script for inter-process connection tests.
///
/// Modes:
///   `--listen --port PORT`   Listen on `tcp/127.0.0.1:PORT`, print LISTENING
///   `--connect --port PORT`  Connect to `tcp/127.0.0.1:PORT`, print CONNECTED
///
/// In both modes, waits `--duration SECONDS` (default 5) then exits cleanly.
void main(List<String> args) async {
  final portIdx = args.indexOf('--port');
  if (portIdx == -1 || portIdx + 1 >= args.length) {
    stderr.writeln(
      'Usage: interprocess_connect.dart --listen|--connect --port <port> '
      '[--duration <seconds>]',
    );
    exit(1);
  }
  final port = args[portIdx + 1];

  final durationIdx = args.indexOf('--duration');
  final duration = (durationIdx != -1 && durationIdx + 1 < args.length)
      ? int.parse(args[durationIdx + 1])
      : 5;

  final isListen = args.contains('--listen');
  final isConnect = args.contains('--connect');

  if (!isListen && !isConnect) {
    stderr.writeln('Must specify --listen or --connect');
    exit(1);
  }

  final config = Config();
  config.insertJson5('mode', '"peer"');

  if (isListen) {
    config.insertJson5('listen/endpoints', '["tcp/127.0.0.1:$port"]');
  } else {
    config.insertJson5('connect/endpoints', '["tcp/127.0.0.1:$port"]');
  }

  final session = Session.open(config: config);
  stdout.writeln(isListen ? 'LISTENING' : 'CONNECTED');
  await Future<void>.delayed(Duration(seconds: duration));
  session.close();
  exit(0);
}
