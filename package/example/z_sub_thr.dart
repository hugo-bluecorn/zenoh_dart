import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:zenoh/zenoh.dart';

const defaultSamples = 10;
const defaultMessages = 100000;

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('samples', abbr: 's', defaultsTo: '$defaultSamples')
    ..addOption('number', abbr: 'n', defaultsTo: '$defaultMessages')
    ..addMultiOption('connect', abbr: 'e')
    ..addMultiOption('listen', abbr: 'l');

  final results = parser.parse(arguments);

  final maxRounds = int.parse(results.option('samples')!);
  final messagesPerRound = int.parse(results.option('number')!);
  final connectEndpoints = results.multiOption('connect');
  final listenEndpoints = results.multiOption('listen');

  Zenoh.initLog('error');

  print('Opening session...');
  final config = Config();
  config.insertJson5('transport/shared_memory/enabled', 'true');
  if (connectEndpoints.isNotEmpty) {
    final json = '[${connectEndpoints.map((e) => '"$e"').join(',')}]';
    config.insertJson5('connect/endpoints', json);
  }
  if (listenEndpoints.isNotEmpty) {
    final json = '[${listenEndpoints.map((e) => '"$e"').join(',')}]';
    config.insertJson5('listen/endpoints', json);
  }
  final session = Session.open(config: config);

  print("Declaring Background Subscriber on 'test/thr'...");
  final bgStream = session.declareBackgroundSubscriber('test/thr');

  var count = 0;
  var finishedRounds = 0;
  var started = false;
  late Stopwatch roundStopwatch;
  late Stopwatch totalStopwatch;

  final exitCompleter = Completer<void>();

  final subscription = bgStream.listen((_) {
    if (count == 0) {
      roundStopwatch = Stopwatch()..start();
      if (!started) {
        totalStopwatch = Stopwatch()..start();
        started = true;
      }
      count++;
    } else if (count < messagesPerRound) {
      count++;
    } else {
      finishedRounds++;
      roundStopwatch.stop();
      final elapsedMs = roundStopwatch.elapsedMicroseconds / 1000.0;
      final throughput = 1000.0 * messagesPerRound / elapsedMs;
      print('${throughput.toStringAsFixed(6)} msg/s');
      count = 0;
      if (finishedRounds > maxRounds) {
        if (!exitCompleter.isCompleted) exitCompleter.complete();
      }
    }
  });

  print('Press CTRL-C to quit...');
  await exitCompleter.future;

  await subscription.cancel();
  totalStopwatch.stop();

  final totalMessages = messagesPerRound * finishedRounds + count;
  final elapsedSeconds = totalStopwatch.elapsedMicroseconds / 1000000.0;
  final overallThroughput = totalMessages / elapsedSeconds;
  print(
    'sent $totalMessages messages over ${elapsedSeconds.toStringAsFixed(6)} seconds (${overallThroughput.toStringAsFixed(6)} msg/s)',
  );

  session.close();
  exit(0);
}
