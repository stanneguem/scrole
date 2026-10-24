import 'package:flutter_test/flutter_test.dart';
import 'package:scrole/app/local_storage/structured/app_cache_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppDatabase instantiation tests', () {
    test('AppDatabase instance can be instantiated', () {
      final appDb = AppDatabase();
      expect(appDb, isNotNull);
    });
  });
}
