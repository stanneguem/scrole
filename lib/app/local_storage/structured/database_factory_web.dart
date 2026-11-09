import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

/// Installs the SQLite/WASM implementation before any app database is opened.
Future<void> configureDatabaseFactory() async {
  databaseFactory = databaseFactoryFfiWeb;
}
