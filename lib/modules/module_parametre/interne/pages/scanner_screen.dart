import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/text_styles.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key, this.onDetect});

  /// Callback appelé avec la valeur brute du QR code détecté.
  /// Si null, l'écran affiche un résultat interne et propose de continuer.
  final ValueChanged<String>? onDetect;

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen>
    with WidgetsBindingObserver {
  late final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
    torchEnabled: false,
  );

  StreamSubscription<BarcodeCapture>? _subscription;
  String? _lastValue;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subscription = _controller.barcodes.listen(_onDetect);
    unawaited(_controller.start());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Libère/relance la caméra proprement quand l'app passe en arrière-plan.
    if (!_controller.value.hasCameraPermission) return;
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(_controller.start());
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        unawaited(_controller.stop());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_subscription?.cancel());
    _subscription = null;
    unawaited(_controller.dispose());
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isProcessing) return;
    final value = capture.barcodes.firstOrNull?.rawValue;
    if (value == null || value == _lastValue) return;

    setState(() {
      _lastValue = value;
      _isProcessing = true;
    });

    if (widget.onDetect != null) {
      widget.onDetect!(value);
      Navigator.of(context).maybePop(value);
    }
  }

  void _scanAgain() {
    setState(() {
      _lastValue = null;
      _isProcessing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            errorBuilder: (context, error) => _ScannerErrorView(error: error),
            placeholderBuilder: (context) => const _ScannerLoadingView(),
          ),

          // Overlay assombri avec fenêtre de visée
          const _ScannerOverlay(),

          // Barre du haut : retour + flash + bascule caméra
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _CircleIconButton(
                      icon: Icons.close_rounded,
                      onTap: () => Navigator.of(context).maybePop(),
                    ),
                    Text(
                      'SCANNER UN QR CODE',
                      style: AppTextStyles.labelMedium.copyWith(
                        color: AppColors.white,
                        letterSpacing: 1,
                      ),
                    ),
                    Row(
                      children: [
                        if (!kIsWeb)
                          ValueListenableBuilder(
                            valueListenable: _controller,
                            builder: (context, value, child) {
                              return _CircleIconButton(
                                icon: value.torchState == TorchState.on
                                    ? Icons.flash_on_rounded
                                    : Icons.flash_off_rounded,
                                onTap: () => _controller.toggleTorch(),
                              );
                            },
                          ),
                        const SizedBox(width: 8),
                        _CircleIconButton(
                          icon: Icons.cameraswitch_rounded,
                          onTap: () => _controller.switchCamera(),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Résultat détecté (uniquement si aucun onDetect externe fourni)
          if (widget.onDetect == null && _lastValue != null)
            Positioned(
              left: 20,
              right: 20,
              bottom: 32,
              child: _ResultCard(
                value: _lastValue!,
                onScanAgain: _scanAgain,
              ),
            ),

          if (widget.onDetect == null && _lastValue == null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 40,
              child: Text(
                'Cadre le QR code dans la zone pour le scanner',
                textAlign: TextAlign.center,
                style: AppTextStyles.body.copyWith(color: _white70),
              ),
            ),
        ],
      ),
    );
  }
}

// =========================================================================
// États : chargement caméra / permission refusée
// =========================================================================

class _ScannerLoadingView extends StatelessWidget {
  const _ScannerLoadingView();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Colors.black,
      child: Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
    );
  }
}

class _ScannerErrorView extends StatelessWidget {
  const _ScannerErrorView({required this.error});

  final MobileScannerException error;

  String get _message {
    switch (error.errorCode) {
      case MobileScannerErrorCode.permissionDenied:
        return kIsWeb
            ? 'Accès à la caméra refusé.\nAutorise-le dans les paramètres de ton navigateur (icône cadenas dans la barre d\'adresse), puis réessaie.'
            : 'Accès à la caméra refusé.\nActive la permission Caméra dans les paramètres de l\'application.';
      case MobileScannerErrorCode.unsupported:
        return 'Le scan n\'est pas supporté sur cet appareil ou ce navigateur.';
      default:
        return 'Impossible d\'accéder à la caméra.\n${error.errorDetails?.message ?? ''}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.videocam_off_rounded, color: AppColors.white, size: 48),
              const SizedBox(height: 16),
              Text(
                _message,
                textAlign: TextAlign.center,
                style: AppTextStyles.body.copyWith(color: AppColors.white),
              ),
              const SizedBox(height: 20),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.white,
                  side: const BorderSide(color: AppColors.white),
                ),
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('Retour'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =========================================================================
// Overlay de visée
// =========================================================================

class _ScannerOverlay extends StatelessWidget {
  const _ScannerOverlay();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: Container(
          width: 260,
          height: 260,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.primary, width: 3),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.55),
                spreadRadius: 2000,
                blurStyle: BlurStyle.solid,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =========================================================================
// Boutons / résultat
// =========================================================================

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.35),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: AppColors.white, size: 20),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.value, required this.onScanAgain});

  final String value;
  final VoidCallback onScanAgain;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'QR code détecté',
            style: AppTextStyles.labelMedium.copyWith(color: AppColors.primary),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: AppTextStyles.body.copyWith(color: AppColors.textPrimaryDark),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.white,
                    side: const BorderSide(color: AppColors.border),
                  ),
                  onPressed: onScanAgain,
                  child: const Text('Scanner à nouveau'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.white,
                  ),
                  onPressed: () => Navigator.of(context).maybePop(value),
                  child: const Text('Utiliser'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

extension on List<Barcode> {
  Barcode? get firstOrNull => isEmpty ? null : first;
}

/// Blanc semi-transparent utilisé uniquement sur le fond noir du scanner
/// (pas ajouté à AppColors car spécifique à cet écran).
const Color _white70 = Color(0x99FFFFFF);