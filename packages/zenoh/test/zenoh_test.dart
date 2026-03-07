import 'package:test/test.dart';
import 'package:zenoh/zenoh.dart';

void main() {
  group('Zenoh', () {
    test('initLog does not throw', () {
      // initLog is idempotent -- safe to call in tests.
      expect(() => Zenoh.initLog('error'), returnsNormally);
    });

    test('initLog accepts various filter levels', () {
      // Subsequent calls are no-ops in zenoh-c, but should not throw.
      expect(() => Zenoh.initLog('warn'), returnsNormally);
      expect(() => Zenoh.initLog('info'), returnsNormally);
    });
  });

  group('Zenoh scout', () {
    test('completes without error', () async {
      final hellos = await Zenoh.scout(timeoutMs: 500);
      expect(hellos, isA<List<Hello>>());
    });

    test('with custom config completes', () async {
      final config = Config();
      final hellos = await Zenoh.scout(config: config, timeoutMs: 500);
      expect(hellos, isA<List<Hello>>());
      // Config should be consumed -- attempting to use it throws StateError
      expect(() => config.nativePtr, throwsStateError);
    });

    test('discovers a peer session', () async {
      // Open a session with multicast on loopback interface
      final listenConfig = Config();
      listenConfig.insertJson5(
          'listen/endpoints', '["tcp/127.0.0.1:17461"]');
      listenConfig.insertJson5(
          'scouting/multicast/interface', '"lo"');
      final session = Session.open(config: listenConfig);
      addTearDown(session.close);

      // Wait for listener to bind and multicast to start
      await Future<void>.delayed(const Duration(seconds: 1));

      // Scout with loopback multicast to find the peer
      final scoutConfig = Config();
      scoutConfig.insertJson5('scouting/multicast/interface', '"lo"');
      final hellos =
          await Zenoh.scout(config: scoutConfig, timeoutMs: 2000);
      expect(hellos, isNotEmpty);

      final peerHello = hellos.firstWhere(
        (h) => h.whatami == WhatAmI.peer,
        orElse: () => throw TestFailure('No peer found in scout results'),
      );
      expect(peerHello.zid.bytes.length, 16);
      // ZID should be non-zero
      expect(peerHello.zid.bytes.any((b) => b != 0), isTrue);
      expect(peerHello.locators, isNotEmpty);
    });

    test('Hello fields are populated correctly', () async {
      final listenConfig = Config();
      listenConfig.insertJson5(
          'listen/endpoints', '["tcp/127.0.0.1:17462"]');
      listenConfig.insertJson5(
          'scouting/multicast/interface', '"lo"');
      final session = Session.open(config: listenConfig);
      addTearDown(session.close);

      await Future<void>.delayed(const Duration(seconds: 1));

      final scoutConfig = Config();
      scoutConfig.insertJson5('scouting/multicast/interface', '"lo"');
      final hellos =
          await Zenoh.scout(config: scoutConfig, timeoutMs: 2000);
      expect(hellos, isNotEmpty);

      final hello = hellos.first;
      expect(hello.zid, isA<ZenohId>());
      expect(hello.zid.bytes.length, 16);
      expect(hello.zid.bytes.any((b) => b != 0), isTrue);
      expect(
          hello.whatami,
          isIn([WhatAmI.router, WhatAmI.peer, WhatAmI.client]));
      expect(hello.locators, isA<List<String>>());
      expect(hello.locators, isNotEmpty);
      // At least one locator should contain a protocol prefix
      expect(hello.locators.any((l) => l.contains('tcp/')), isTrue);
    });

    test('Hello.toString produces readable output', () async {
      final listenConfig = Config();
      listenConfig.insertJson5(
          'listen/endpoints', '["tcp/127.0.0.1:17463"]');
      listenConfig.insertJson5(
          'scouting/multicast/interface', '"lo"');
      final session = Session.open(config: listenConfig);
      addTearDown(session.close);

      await Future<void>.delayed(const Duration(seconds: 1));

      final scoutConfig = Config();
      scoutConfig.insertJson5('scouting/multicast/interface', '"lo"');
      final hellos =
          await Zenoh.scout(config: scoutConfig, timeoutMs: 2000);
      expect(hellos, isNotEmpty);

      final str = hellos.first.toString();
      expect(str, contains('Hello'));
      expect(str, contains(hellos.first.zid.toHexString()));
      expect(str, contains(hellos.first.whatami.name));
      // Should contain at least one locator
      expect(str, contains('tcp/'));
    });

    test('with consumed config throws StateError', () async {
      final config = Config();
      // Consume the config by opening a session
      final session = Session.open(config: config);
      addTearDown(session.close);

      // Now config is consumed -- scout should throw
      expect(
        () => Zenoh.scout(config: config, timeoutMs: 500),
        throwsStateError,
      );
    });
  });
}
