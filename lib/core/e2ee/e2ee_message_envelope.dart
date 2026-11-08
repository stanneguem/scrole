import 'dart:convert';
import 'dart:typed_data';

/// Opaque transport representation of one MLS wire message.
///
/// This object intentionally has no plaintext, preview, media URL, or decrypted
/// content field. It is a transport DTO only; it does not encrypt or decrypt.
class E2eeMessageEnvelope {
  E2eeMessageEnvelope({
    required this.messageId,
    required this.conversationId,
    required this.groupId,
    required this.senderDeviceId,
    required this.epoch,
    required this.protocolVersion,
    required this.ciphersuite,
    required Uint8List ciphertext,
  }) : ciphertext = Uint8List.fromList(ciphertext);

  static const currentProtocolVersion = 1;
  static const currentProtocol = 'MLS/1.0';

  final String messageId;
  final String conversationId;
  final String groupId;
  final String senderDeviceId;
  final int epoch;
  final int protocolVersion;
  final String ciphersuite;
  final Uint8List ciphertext;

  Map<String, dynamic> toJson() {
    _validate();
    return {
      'message_id': messageId,
      'conversation_id': conversationId,
      'group_id': groupId,
      'sender_device_id': senderDeviceId,
      'epoch': epoch,
      'protocol_version': protocolVersion,
      'protocol': currentProtocol,
      'ciphersuite': ciphersuite,
      'ciphertext': base64UrlEncode(ciphertext),
    };
  }

  factory E2eeMessageEnvelope.fromJson(Map<String, dynamic> json) {
    final protocol = json['protocol'];
    if (protocol != currentProtocol) {
      throw const FormatException('Unsupported E2EE message protocol.');
    }
    final rawCiphertext = json['ciphertext'];
    if (rawCiphertext is! String || rawCiphertext.isEmpty) {
      throw const FormatException('Missing E2EE ciphertext.');
    }

    final envelope = E2eeMessageEnvelope(
      messageId: _requiredString(json, 'message_id'),
      conversationId: _requiredString(json, 'conversation_id'),
      groupId: _requiredString(json, 'group_id'),
      senderDeviceId: _requiredString(json, 'sender_device_id'),
      epoch: _requiredInt(json, 'epoch'),
      protocolVersion: _requiredInt(json, 'protocol_version'),
      ciphersuite: _requiredString(json, 'ciphersuite'),
      ciphertext: Uint8List.fromList(
        base64Url.decode(base64Url.normalize(rawCiphertext)),
      ),
    );
    envelope._validate();
    return envelope;
  }

  void _validate() {
    if (messageId.trim().isEmpty ||
        conversationId.trim().isEmpty ||
        groupId.trim().isEmpty ||
        senderDeviceId.trim().isEmpty) {
      throw ArgumentError('E2EE routing identifiers must not be empty.');
    }
    if (epoch < 0) {
      throw ArgumentError.value(epoch, 'epoch', 'must be non-negative');
    }
    if (protocolVersion != currentProtocolVersion) {
      throw ArgumentError.value(
        protocolVersion,
        'protocolVersion',
        'unsupported protocol version',
      );
    }
    if (ciphersuite != 'MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519') {
      throw ArgumentError.value(ciphersuite, 'ciphersuite', 'unsupported');
    }
    if (ciphertext.isEmpty) {
      throw ArgumentError('MLS ciphertext must not be empty.');
    }
  }

  static String _requiredString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('Missing or invalid $key.');
    }
    return value;
  }

  static int _requiredInt(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! int) throw FormatException('Missing or invalid $key.');
    return value;
  }
}
