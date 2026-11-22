import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:lottie/lottie.dart';

class MaintenanceScreen extends StatelessWidget {
  const MaintenanceScreen({super.key});

  static const Map<String, Map<String, String>> _copy = {
    'fr': {
      'title': 'Scrole est en maintenance',
      'message': 'Nous effectuons actuellement une maintenance afin d’améliorer Scrole. Le service sera de nouveau disponible bientôt. Merci de patienter.',
    },
    'en': {
      'title': 'Scrole is under maintenance',
      'message': 'We’re performing maintenance to improve Scrole. The service will be available again soon. Thank you for your patience.',
    },
    'es': {
      'title': 'Scrole está en mantenimiento',
      'message': 'Estamos realizando tareas de mantenimiento para mejorar Scrole. El servicio volverá a estar disponible pronto. Gracias por tu paciencia.',
    },
    'de': {
      'title': 'Scrole wird gewartet',
      'message': 'Wir führen Wartungsarbeiten durch, um Scrole zu verbessern. Der Dienst ist bald wieder verfügbar. Vielen Dank für deine Geduld.',
    },
    'it': {
      'title': 'Scrole è in manutenzione',
      'message': 'Stiamo effettuando interventi di manutenzione per migliorare Scrole. Il servizio sarà di nuovo disponibile a breve. Grazie per la pazienza.',
    },
    'pt': {
      'title': 'Scrole está em manutenção',
      'message': 'Estamos realizando uma manutenção para melhorar o Scrole. O serviço estará disponível novamente em breve. Obrigado pela paciência.',
    },
    'zh': {
      'title': 'Scrole 正在维护',
      'message': '我们正在进行维护，以改进 Scrole。服务很快会恢复。感谢您的耐心等待。',
    },
    'ja': {
      'title': 'Scrole はメンテナンス中です',
      'message': 'Scrole の改善のため、現在メンテナンスを行っています。サービスはまもなく再開します。ご理解いただきありがとうございます。',
    },
    'ru': {
      'title': 'Scrole находится на обслуживании',
      'message': 'Мы проводим техническое обслуживание, чтобы улучшить Scrole. Скоро сервис снова станет доступен. Спасибо за терпение.',
    },
  };

  Map<String, String> get _localizedCopy {
    final locale = (Get.locale?.languageCode ?? Get.deviceLocale?.languageCode ?? 'fr').toLowerCase();
    return _copy[locale] ?? _copy['fr']!;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final size = MediaQuery.of(context).size;
    final copy = _localizedCopy;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: size.width * 0.75,
                    height: size.width * 0.75,
                    child: Lottie.asset(
                      'assets/lotties/Under Maintenance.json',
                      fit: BoxFit.contain,
                      repeat: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    copy['title']!,
                    style: textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colorScheme.onSurface,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    copy['message']!,
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
