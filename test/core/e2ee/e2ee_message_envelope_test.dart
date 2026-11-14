import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrole/core/e2ee/e2ee_message_envelope.dart';

void main() {
  group('E2eeMessageEnvelope', () {
    E2eeMessageEnvelope sample() => E2eeMessageEnvelope(
          messageId: 'message-1',
          conversationId: 'conversation-1',
          groupId: 'bWxzLWdyb3Vw',
          senderDeviceId: 'device-1',
          epoch: 7,
          protocolVersion: E2eeMessageEnvelope.currentProtocolVersion,
          ciphersuite: 'MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519',
          ciphertext: Uint8List.fromList([0, 1, 2, 255]),
        );

    test('round-trips opaque ciphertext and routing metadata', () {
      final original = sample();
      final decoded = E2eeMessageEnvelope.fromJson(original.toJson());

      expect(decoded.messageId, original.messageId);
      expect(decoded.conversationId, original.conversationId);
      expect(decoded.groupId, original.groupId);
      expect(decoded.senderDeviceId, original.senderDeviceId);
      expect(decoded.epoch, original.epoch);
      expect(decoded.ciphertext, orderedEquals(original.ciphertext));
      expect(decoded.toJson().containsKey('content'), isFalse);
      expect(decoded.toJson().containsKey('preview'), isFalse);
    });

    test('rejects unsupported protocol', () {
      final json = sample().toJson()..['protocol'] = 'plaintext/v0';
      expect(
        () => E2eeMessageEnvelope.fromJson(json),
        throwsFormatException,
      );
    });

    test('rejects empty ciphertext', () {
      expect(
        () => E2eeMessageEnvelope(
          messageId: 'message-1',
          conversationId: 'conversation-1',
          groupId: 'group-1',
          senderDeviceId: 'device-1',
          epoch: 0,
          protocolVersion: 1,
          ciphersuite: 'MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519',
          ciphertext: Uint8List(0),
        ).toJson(),
        throwsArgumentError,
      );
    });

    test('rejects negative epoch and unknown ciphersuite', () {
      expect(
        () => E2eeMessageEnvelope(
          messageId: 'message-1',
          conversationId: 'conversation-1',
          groupId: 'group-1',
          senderDeviceId: 'device-1',
          epoch: -1,
          protocolVersion: 1,
          ciphersuite: 'MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519',
          ciphertext: Uint8List.fromList([1]),
        ).toJson(),
        throwsArgumentError,
      );
      expect(
        () => E2eeMessageEnvelope(
          messageId: 'message-1',
          conversationId: 'conversation-1',
          groupId: 'group-1',
          senderDeviceId: 'device-1',
          epoch: 0,
          protocolVersion: 1,
          ciphersuite: 'unknown',
          ciphertext: Uint8List.fromList([1]),
        ).toJson(),
        throwsArgumentError,
      );
    });
  });
}
