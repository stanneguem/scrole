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

    test('accepts an existing 256-bit key without returning its bytes', () async {
      final expected = List<int>.generate(32, (i) => i);
      when(() => storage.read(key: any(named: 'key'))).thenAnswer(
        (_) async => base64UrlEncode(expected),
      );

      await expectLater(
        manager.ensureProvisioned(userId: 'user-a', deviceId: 'device-a'),
        completes,
      );
      verify(() => storage.read(
            key: 'scrole.e2ee.mls.storage_key.v1.user-a.device-a',
          )).called(1);
      verifyNever(() => storage.write(
            key: any(named: 'key'),
            value: any(named: 'value'),
          ));
    });

    test('creates and persists a 32-byte key without returning it', () async {
      when(() => storage.read(key: any(named: 'key')))
          .thenAnswer((_) async => null);
      when(() => storage.write(
            key: any(named: 'key'),
            value: any(named: 'value'),
          )).thenAnswer((_) async {});

      await manager.ensureProvisioned(userId: 'user-a', deviceId: 'device-a');

      final captured = verify(() => storage.write(
            key: 'scrole.e2ee.mls.storage_key.v1.user-a.device-a',
            value: captureAny(named: 'value'),
          )).captured.single as String;
      expect(base64Url.decode(captured), hasLength(32));
    });

    test('rejects a stored key with the wrong length', () async {
      when(() => storage.read(key: any(named: 'key')))
          .thenAnswer((_) async => base64UrlEncode([1, 2, 3]));

      await expectLater(
        manager.ensureProvisioned(userId: 'user-a', deviceId: 'device-a'),
        throwsA(isA<StateError>()),
      );
    });

    test('rejects empty account or device identifiers', () {
      expect(
        () => manager.ensureProvisioned(userId: ' ', deviceId: 'device-a'),
        throwsArgumentError,
      );
      expect(
        () => manager.ensureProvisioned(userId: 'user-a', deviceId: ''),
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

      await Future.wait([
        manager.ensureProvisioned(userId: 'user-b', deviceId: 'device-b'),
        manager.ensureProvisioned(userId: 'user-b', deviceId: 'device-b'),
      ]);

      expect(reads, 1);
      verify(() => storage.write(
            key: 'scrole.e2ee.mls.storage_key.v1.user-b.device-b',
            value: any(named: 'value'),
          )).called(1);
    });
  });
}
