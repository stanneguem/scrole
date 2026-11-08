import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrole/core/e2ee/e2ee_transport_repository.dart';

void main() {
  group('E2eeTransportRepository bytea codec', () {
    test('encodes ciphertext as PostgreSQL hex bytea without text conversion', () {
      expect(
        E2eeTransportRepository.encodePostgresBytea(
          Uint8List.fromList([0x00, 0x01, 0x0a, 0xff]),
        ),
        r'\x00010aff',
      );
    });

    test('encodes empty byte arrays without inventing a payload', () {
      expect(
        E2eeTransportRepository.encodePostgresBytea(Uint8List(0)),
        r'\x',
      );
    });

    test('preserves leading zero bytes', () {
      expect(
        E2eeTransportRepository.encodePostgresBytea(
          Uint8List.fromList([0x00, 0x00, 0x7f]),
        ),
        r'\x00007f',
      );
    });
  });
}
