import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../centre/models/activity_model.dart';
import '../../centre/models/checkin_model.dart';
import '../../centre/repositories/event_repository.dart';

enum ScanState {
  idle,
  scanning,
  checkingPresence,
  presenceValidated,
  alreadyPresent,
  activitySelection,
  activityValidating,
  activityValidated,
  userNotRegistered,
  eventNotStarted,
  permissionDenied,
  activityUnavailable,
  networkError,
  scanError,
}

class QrScanController extends GetxController {
  final String eventId;
  final String? eventActivityId;
  final DateTime? eventStartsAt;
  final EventRepository _repository;

  final MobileScannerController mobileScannerController = MobileScannerController();

  QrScanController({
    required this.eventId,
    this.eventActivityId,
    this.eventStartsAt,
    EventRepository? repository,
  }) : _repository = repository ?? Get.find<EventRepository>();

  final Rx<ScanState> scanState = ScanState.idle.obs;
  final RxBool isProcessing = false.obs;
  final Rxn<CheckinScanResult> lastResult = Rxn<CheckinScanResult>();
  final RxnString errorMessage = RxnString();
  final RxnString scannedUserId = RxnString();
  final Rxn<AvailableActivityModel> selectedActivity = Rxn<AvailableActivityModel>();

  @override
  void onInit() {
    super.onInit();
    scanState.value = ScanState.scanning;
  }

  @override
  void onClose() {
    mobileScannerController.dispose();
    super.onClose();
  }

  Future<void> onScan(BarcodeCapture capture) async {
    if (isProcessing.value || (scanState.value != ScanState.scanning && scanState.value != ScanState.idle)) {
      return;
    }

    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final String? code = barcodes.first.rawValue;
    if (code == null || code.isEmpty) return;

    isProcessing.value = true;
    mobileScannerController.stop();

    String targetUserId = '';
    if (code.startsWith('scrole_pass:')) {
      final parts = code.split(':');
      try {
        final userIdPart = parts.firstWhere((p) => p.startsWith('user='));
        targetUserId = userIdPart.split('=')[1];
      } catch (_) {
        targetUserId = code;
      }
    } else {
      targetUserId = code.trim();
    }

    if (targetUserId.isEmpty) {
      _setErrorState(ScanState.scanError, 'checkin_generic_error_msg'.tr);
      return;
    }

    scannedUserId.value = targetUserId;
    scanState.value = ScanState.checkingPresence;

    try {
      final result = await _repository.scanCheckinOptimistic(
        eventId: eventId,
        targetUserId: targetUserId,
        activityId: eventActivityId,
      );

      lastResult.value = result;

      if (result.presenceCreee) {
        scanState.value = ScanState.presenceValidated;
      } else if (result.alreadyPresent) {
        if (result.availableActivities.isNotEmpty) {
          scanState.value = ScanState.activitySelection;
        } else {
          scanState.value = ScanState.alreadyPresent;
        }
      } else {
        scanState.value = ScanState.presenceValidated;
      }
    } catch (e) {
      debugPrint('[QrScanController Error] $e');
      _mapErrorToState(e);
    } finally {
      isProcessing.value = false;
    }
  }

  Future<void> validateActivity(AvailableActivityModel activity, {int quantity = 1}) async {
    final userId = scannedUserId.value;
    if (userId == null || userId.isEmpty) return;

    selectedActivity.value = activity;
    scanState.value = ScanState.activityValidating;
    isProcessing.value = true;

    try {
      final result = await _repository.scanCheckinOptimistic(
        eventId: eventId,
        targetUserId: userId,
        activityId: activity.id,
        quantity: quantity,
      );

      lastResult.value = result;
      scanState.value = ScanState.activityValidated;
    } catch (e) {
      debugPrint('[QrScanController Error] $e');
      _mapErrorToState(e);
    } finally {
      isProcessing.value = false;
    }
  }

  void resetScan() {
    scannedUserId.value = null;
    lastResult.value = null;
    errorMessage.value = null;
    selectedActivity.value = null;
    scanState.value = ScanState.scanning;
    isProcessing.value = false;
    mobileScannerController.start();
  }

  void _mapErrorToState(dynamic error) {
    final str = error.toString().toLowerCase();

    if (str.contains('pas enregistrée') ||
        str.contains('non enregistré') ||
        str.contains('pas enregistre') ||
        str.contains('not_registered') ||
        str.contains('not registered') ||
        str.contains('pas inscrit') ||
        str.contains('non inscrit')) {
      _setErrorState(
        ScanState.userNotRegistered,
        'checkin_not_registered_msg'.tr,
      );
    } else if (str.contains('not_started') ||
        str.contains('starts_at') ||
        str.contains('pas encore commencé') ||
        str.contains('pas commencé')) {
      String formattedDate = '';
      if (eventStartsAt != null) {
        try {
          final lang = Get.locale?.languageCode ?? 'fr';
          formattedDate = DateFormat('d MMMM yyyy • HH:mm', lang).format(eventStartsAt!);
        } catch (_) {
          formattedDate = eventStartsAt.toString().substring(0, 16);
        }
      }

      _setErrorState(
        ScanState.eventNotStarted,
        'checkin_not_started_msg'.trParams({'date': formattedDate}),
      );
    } else if (str.contains('not_authorized') ||
        str.contains('unauthorized') ||
        str.contains('non autorisé') ||
        str.contains('permission') ||
        str.contains('staff') ||
        str.contains('42501')) {
      _setErrorState(
        ScanState.permissionDenied,
        'checkin_permission_denied_msg'.tr,
      );
    } else if (str.contains('activity_unavailable') ||
        str.contains('indisponible') ||
        str.contains('not_found')) {
      _setErrorState(
        ScanState.activityUnavailable,
        'checkin_activity_unavailable_msg'.tr,
      );
    } else if (str.contains('network') || str.contains('socket') || str.contains('offline') || str.contains('connection')) {
      _setErrorState(
        ScanState.networkError,
        'checkin_network_error_msg'.tr,
      );
    } else {
      _setErrorState(
        ScanState.scanError,
        'checkin_generic_error_msg'.tr,
      );
    }
  }

  void _setErrorState(ScanState state, String message) {
    errorMessage.value = message;
    scanState.value = state;
  }
}
