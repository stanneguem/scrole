import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scrole/core/e2ee/e2ee_device_identity.dart';

class _MockSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  group('E2eeDeviceIdentity', () {
    late _MockSecureStorage storage;
    late E2eeDeviceIdentity identity;

    setUp(() {
      storage = _MockSecureStorage();
      identity = E2eeDeviceIdentity(storage: storage);
    });

    test('returns the persisted UUIDv4 for an account', () async {
      const persisted = 'a2c0d9e1-4f11-4b2a-9d18-11b6c98f7e20';
      when(() => storage.read(key: any(named: 'key')))
          .thenAnswer((_) async => persisted);

      final result = await identity.getOrCreate(userId: 'user-1');

      expect(result, persisted);
      verify(() => storage.read(
            key: 'scrole.e2ee.device_identity.v1.user-1',
          )).called(1);
      verifyNever(() => storage.write(
            key: any(named: 'key'),
            value: any(named: 'value'),
          ));
    });

    test('creates a UUIDv4 and persists it when none exists', () async {
      when(() => storage.read(key: any(named: 'key')))
          .thenAnswer((_) async => null);
      when(() => storage.write(
            key: any(named: 'key'),
            value: any(named: 'value'),
          )).thenAnswer((_) async {});

      final result = await identity.getOrCreate(userId: 'user-2');

      expect(
        result,
        matches(RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-'
          r'[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        )),
      );
      verify(() => storage.write(
            key: 'scrole.e2ee.device_identity.v1.user-2',
            value: result,
          )).called(1);
    });

    test('rejects malformed persisted identity instead of replacing it', () async {
      when(() => storage.read(key: any(named: 'key')))
          .thenAnswer((_) async => 'not-a-uuid');

      await expectLater(
        identity.getOrCreate(userId: 'user-3'),
        throwsA(isA<StateError>()),
      );
      verifyNever(() => storage.write(
            key: any(named: 'key'),
            value: any(named: 'value'),
          ));
    });

    test('does not create an identity during lookup', () async {
      when(() => storage.read(key: any(named: 'key')))
          .thenAnswer((_) async => null);

      expect(await identity.getExisting(userId: 'user-4'), isNull);
      verifyNever(() => storage.write(
            key: any(named: 'key'),
            value: any(named: 'value'),
          ));
    });

    test('serializes concurrent creation for the same account', () async {
      var reads = 0;
      when(() => storage.read(key: any(named: 'key'))).thenAnswer((_) async {
        reads++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return null;
      });
      when(() => storage.write(
            key: any(named: 'key'),
            value: any(named: 'value'),
          )).thenAnswer((_) async {});

      final results = await Future.wait([
        identity.getOrCreate(userId: 'same-user'),
        identity.getOrCreate(userId: 'same-user'),
      ]);

      expect(results[0], results[1]);
      expect(reads, 1);
      verify(() => storage.write(
            key: 'scrole.e2ee.device_identity.v1.same-user',
            value: results.first,
          )).called(1);
    });

    test('keeps identities separate between accounts', () async {
      final values = <String, String>{};
      when(() => storage.read(key: any(named: 'key'))).thenAnswer((invocation) async {
        return values[invocation.namedArguments[#key] as String];
      });
      when(() => storage.write(
            key: any(named: 'key'),
            value: any(named: 'value'),
          )).thenAnswer((invocation) async {
        values[invocation.namedArguments[#key] as String] =
            invocation.namedArguments[#value] as String;
      });

      final first = await identity.getOrCreate(userId: 'account-a');
      final second = await identity.getOrCreate(userId: 'account-b');

      expect(first, isNot(second));
      expect(values, hasLength(2));
    });
  });
}
