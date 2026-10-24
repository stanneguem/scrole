import 'dart:async';
import 'package:flutter/foundation.dart';

/// Horloge globale de démarrage partagée par tous les points de mesure [BootTrace].
final Stopwatch bootClock = Stopwatch()..start();

/// Journalise un événement instantané avec l'horodatage relatif à [bootClock].
void bootLog(String label) {
  if (kDebugMode || kProfileMode) {
    debugPrint('[BootTrace] $label @ ${bootClock.elapsedMilliseconds} ms');
  }
}

/// Mesure la durée d'exécution synchrone d'un bloc de code.
T bootMeasure<T>(String label, T Function() fn) {
  if (!kDebugMode && !kProfileMode) {
    return fn();
  }
  final startMs = bootClock.elapsedMilliseconds;
  final sw = Stopwatch()..start();
  final result = fn();
  final durationMs = sw.elapsedMilliseconds;
  debugPrint('[BootTrace] $label : $durationMs ms (@ $startMs ms)');
  return result;
}

/// Mesure la durée d'exécution asynchrone d'une Future.
Future<T> bootMeasureAsync<T>(String label, Future<T> Function() fn) async {
  if (!kDebugMode && !kProfileMode) {
    return await fn();
  }
  final startMs = bootClock.elapsedMilliseconds;
  final sw = Stopwatch()..start();
  final result = await fn();
  final durationMs = sw.elapsedMilliseconds;
  debugPrint('[BootTrace] $label : $durationMs ms (@ $startMs ms)');
  return result;
}
