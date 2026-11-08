import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scrole/core/e2ee/e2ee_transport_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _MockSupabaseClient extends Mock implements SupabaseClient {}

void main() {
  late _MockSupabaseClient client;
  late E2eeTransportRepository repository;

  setUp(() {
    client = _MockSupabaseClient();
    repository = E2eeTransportRepository(client);
  });

  group('E2eeTransportRepository', () {
    test('sends only encoded ciphertext through the MLS RPC', () async {
      when(
        () => client.rpc(
          'e2ee_send_group_message',
          params: any(named: 'params'),
        ),
      ).thenAnswer((_) async => 'message-uuid');

      final result = await repository.sendCiphertext(
        groupId: 'group-uuid',
        epoch: 4,
        senderDeviceId: 'device-uuid',
        ciphertext: Uint8List.fromList([0x01, 0x0a, 0xff]),
      );

      expect(result, 'message-uuid');
      final captured = verify(
        () => client.rpc(
          'e2ee_send_group_message',
          params: captureAny(named: 'params'),
        ),
      ).captured.single as Map<String, dynamic>;
      expect(captured['p_group_id'], 'group-uuid');
      expect(captured['p_epoch'], 4);
      expect(captured['p_sender_device_id'], 'device-uuid');
      expect(captured['p_ciphertext'], r'\x010aff');
      expect(captured.keys, isNot(contains('content')));
      expect(captured.keys, isNot(contains('preview')));
    });

    test('rejects empty ciphertext before contacting Supabase', () async {
      await expectLater(
        repository.sendCiphertext(
          groupId: 'group-uuid',
          epoch: 0,
          senderDeviceId: 'device-uuid',
          ciphertext: Uint8List(0),
        ),
        throwsArgumentError,
      );
      verifyNever(
        () => client.rpc(
          any(),
          params: any(named: 'params'),
        ),
      );
    });

    test('rejects duplicate device ids in an MLS commit roster', () async {
      await expectLater(
        repository.applyCommit(
          groupId: 'group-uuid',
          expectedEpoch: 0,
          commitCiphertext: Uint8List.fromList([1]),
          activeDeviceIds: ['device-a', 'device-a'],
        ),
        throwsArgumentError,
      );
      verifyNever(
        () => client.rpc(
          any(),
          params: any(named: 'params'),
        ),
      );
    });

    test('rejects a scope other than direct or community salon', () async {
      await expectLater(
        repository.createGroup(
          scopeType: 'admin',
          scopeId: 'scope-uuid',
          mlsGroupId: Uint8List.fromList([1]),
          creatorDeviceId: 'device-uuid',
        ),
        throwsArgumentError,
      );
      verifyNever(
        () => client.rpc(
          any(),
          params: any(named: 'params'),
        ),
      );
    });
  });
}
