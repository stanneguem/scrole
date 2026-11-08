import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scrole/core/e2ee/secure_mls_storage_key.dart';

class _MockSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  group('SecureMlsStorageKey', () {
    late _MockSecureStorage storage;
    late SecureMlsStorageKey manager;

    setUp(() {
      storage = _MockSecureStorage();
      manager = SecureMlsStorageKey(storage: storage);
    });

    test('returns the existing 256-bit key', () async {
      final expected = List<int>.generate(32, (i) => i);
      when(() => storage.read(key: any(named: 'key'))).thenAnswer(
        (_) async => base64UrlEncode(expected),
      );

      final actual = await manager.getOrCreate(
        userId: 'user-a',
        deviceId: 'device-a',
      );

      expect(actual, expected);
      verify(() => storage.read(
            key: 'scrole.e2ee.mls.storage_key.v1.user-a.device-a',
          )).called(1);
      verifyNever(() => storage.write(
            key: any(named: 'key'),
            value: any(named: 'value'),
          ));
    });

    test('creates and persists a 32-byte key when missing', () async {
      when(() => storage.read(key: any(named: 'key')))
          .thenAnswer((_) async => null);
      when(() => storage.write(
            key: any(named: 'key'),
            value: any(named: 'value'),
          )).thenAnswer((_) async {});

      final key = await manager.getOrCreate(
        userId: 'user-a',
        deviceId: 'device-a',
      );

      expect(key, hasLength(32));
      verify(() => storage.write(
            key: 'scrole.e2ee.mls.storage_key.v1.user-a.device-a',
            value: base64UrlEncode(key),
          )).called(1);
    });

    test('rejects a stored key with the wrong length', () async {
      when(() => storage.read(key: any(named: 'key')))
          .thenAnswer((_) async => base64UrlEncode([1, 2, 3]));

      await expectLater(
        manager.getOrCreate(userId: 'user-a', deviceId: 'device-a'),
        throwsA(isA<StateError>()),
      );
    });

    test('rejects empty account or device identifiers', () async {
      await expectLater(
        manager.getOrCreate(userId: ' ', deviceId: 'device-a'),
        throwsArgumentError,
      );
      await expectLater(
        manager.getOrCreate(userId: 'user-a', deviceId: ''),
        throwsArgumentError,
      );
      verifyNever(() => storage.read(key: any(named: 'key')));
    });

    test('serializes concurrent key creation for the same device', () async {
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
        manager.getOrCreate(userId: 'user-b', deviceId: 'device-b'),
        manager.getOrCreate(userId: 'user-b', deviceId: 'device-b'),
      ]);

      expect(results[0], results[1]);
      expect(reads, 1);
      verify(() => storage.write(
            key: 'scrole.e2ee.mls.storage_key.v1.user-b.device-b',
            value: base64UrlEncode(results.first),
          )).called(1);
    });
  });
}
