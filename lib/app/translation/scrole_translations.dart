import 'package:get/get.dart';

import 'app_translation.dart';
import 'app_translation_additions.dart';

/// Composition of the historical translations and the translations added
/// for the current UI flows. Arabic is deliberately excluded at runtime.
class ScroleTranslations extends Translations {
  static Map<String, Map<String, String>>? _cachedKeys;

  @override
  Map<String, Map<String, String>> get keys {
    if (_cachedKeys != null) return _cachedKeys!;

    final merged = <String, Map<String, String>>{};
    final base = AppTranslations().keys;

    for (final entry in base.entries) {
      if (entry.key == 'ar') continue;
      merged[entry.key] = Map<String, String>.from(entry.value);
    }

    for (final entry in AppTranslationAdditions.keys.entries) {
      merged.putIfAbsent(entry.key, () => <String, String>{});
      merged[entry.key]!.addAll(entry.value);
    }

    _cachedKeys = merged;
    return _cachedKeys!;
  }
}
