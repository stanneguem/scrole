import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:get/get.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import '../../shared/etats/connectivity_states.dart';

class ConnectivityService extends GetxService {
  final Connectivity _connectivity = Connectivity();
  final InternetConnection _internetChecker = InternetConnection();

  final RxBool isConnected = true.obs;
  final Rx<ConnectionBannerState> bannerState = ConnectionBannerState.hidden.obs;

  StreamSubscription? _connectivitySub;
  StreamSubscription? _internetSub;

  Future<ConnectivityService> init() async {
    // Initialisation immédiate sans attendre le réseau
    _checkInitialConnection();
    _listenConnectivity();
    return this;
  }

  Future<void> _checkInitialConnection() async {
    try {
      // On vérifie en arrière-plan pour ne pas bloquer le démarrage de l'app
      final status = await _internetChecker.hasInternetAccess.timeout(const Duration(seconds: 2));
      isConnected.value = status;
    } catch (_) {
      // En cas d'erreur ou timeout, on considère qu'on est hors-ligne par sécurité
      // ou on garde la valeur par défaut (true) pour ne pas effrayer l'utilisateur
      isConnected.value = false;
    }
  }

  void _listenConnectivity() {
    _connectivitySub = _connectivity.onConnectivityChanged.listen((results) {
      final hasInterface = results.isNotEmpty && !results.contains(ConnectivityResult.none);
      if (!hasInterface) isConnected.value = false;
    });

    _internetSub = _internetChecker.onStatusChange.listen((s) {
      final wasOffline = !isConnected.value;
      final currentConnected = s == InternetStatus.connected;
      isConnected.value = currentConnected;

      if (wasOffline && currentConnected) {
        bannerState.value = ConnectionBannerState.backOnline;
        Future.delayed(const Duration(seconds: 2), () {
          if (bannerState.value == ConnectionBannerState.backOnline) {
            bannerState.value = ConnectionBannerState.hidden;
          }
        });
      } else if (!currentConnected) {
        bannerState.value = ConnectionBannerState.offline;
      } else {
        bannerState.value = ConnectionBannerState.hidden;
      }
    });
  }

  Future<bool> checkConnection() async {
    final result = await _internetChecker.hasInternetAccess;
    isConnected.value = result;
    return result;
  }

  Stream<InternetStatus> get onStatusChange => _internetChecker.onStatusChange;

  @override
  void onClose() {
    _connectivitySub?.cancel();
    _internetSub?.cancel();
    super.onClose();
  }
}
