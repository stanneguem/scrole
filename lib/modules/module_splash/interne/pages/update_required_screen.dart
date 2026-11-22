import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:lottie/lottie.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/service_global/app_config_service.dart';

class UpdateRequiredScreen extends StatelessWidget {
  const UpdateRequiredScreen({super.key});

  static const Map<String, Map<String, String>> _translations = {
    'fr': {
      'title': 'Une mise à jour est nécessaire',
      'message': 'Une nouvelle version de Scrole est disponible. Mets l’application à jour pour continuer à profiter de toutes les fonctionnalités.',
      'button': 'Mettre à jour maintenant',
      'version': 'Dernière version',
      'store_error_title': 'Boutique indisponible',
      'store_error': 'Le lien de téléchargement n’est pas configuré ou ne peut pas être ouvert. Réessaie plus tard.',
      'badge': 'Mise à jour obligatoire',
    },
    'en': {
      'title': 'An update is required',
      'message': 'A new version of Scrole is available. Update the app to keep enjoying all its features.',
      'button': 'Update now',
      'version': 'Latest version',
      'store_error_title': 'Store unavailable',
      'store_error': 'The download link is missing or could not be opened. Please try again later.',
      'badge': 'Required update',
    },
    'es': {
      'title': 'Es necesario actualizar',
      'message': 'Hay una nueva versión de Scrole disponible. Actualiza la aplicación para seguir disfrutando de todas sus funciones.',
      'button': 'Actualizar ahora',
      'version': 'Última versión',
      'store_error_title': 'Tienda no disponible',
      'store_error': 'El enlace de descarga no está configurado o no se puede abrir. Inténtalo más tarde.',
      'badge': 'Actualización obligatoria',
    },
    'de': {
      'title': 'Ein Update ist erforderlich',
      'message': 'Eine neue Version von Scrole ist verfügbar. Aktualisiere die App, um alle Funktionen weiterhin nutzen zu können.',
      'button': 'Jetzt aktualisieren',
      'version': 'Neueste Version',
      'store_error_title': 'Store nicht verfügbar',
      'store_error': 'Der Download-Link fehlt oder kann nicht geöffnet werden. Bitte versuche es später erneut.',
      'badge': 'Erforderliches Update',
    },
    'it': {
      'title': 'È necessario un aggiornamento',
      'message': 'È disponibile una nuova versione di Scrole. Aggiorna l’app per continuare a utilizzare tutte le funzionalità.',
      'button': 'Aggiorna ora',
      'version': 'Ultima versione',
      'store_error_title': 'Store non disponibile',
      'store_error': 'Il link per il download non è configurato o non può essere aperto. Riprova più tardi.',
      'badge': 'Aggiornamento obbligatorio',
    },
    'pt': {
      'title': 'É necessária uma atualização',
      'message': 'Está disponível uma nova versão do Scrole. Atualize a aplicação para continuar a utilizar todas as funcionalidades.',
      'button': 'Atualizar agora',
      'version': 'Versão mais recente',
      'store_error_title': 'Loja indisponível',
      'store_error': 'O link de transferência não está configurado ou não pode ser aberto. Tente novamente mais tarde.',
      'badge': 'Atualização obrigatória',
    },
    'zh': {
      'title': '需要更新应用',
      'message': 'Scrole 有新版本可用。请更新应用，以继续使用所有功能。',
      'button': '立即更新',
      'version': '最新版本',
      'store_error_title': '应用商店不可用',
      'store_error': '下载链接尚未配置或无法打开，请稍后重试。',
      'badge': '必须更新',
    },
    'ja': {
      'title': 'アップデートが必要です',
      'message': 'Scrole の新しいバージョンが公開されています。すべての機能を引き続き利用するには、アプリを更新してください。',
      'button': '今すぐ更新',
      'version': '最新バージョン',
      'store_error_title': 'ストアを利用できません',
      'store_error': 'ダウンロードリンクが設定されていないか、開けません。後でもう一度お試しください。',
      'badge': '必須アップデート',
    },
    'ru': {
      'title': 'Необходимо обновить приложение',
      'message': 'Доступна новая версия Scrole. Обновите приложение, чтобы продолжить пользоваться всеми функциями.',
      'button': 'Обновить сейчас',
      'version': 'Последняя версия',
      'store_error_title': 'Магазин недоступен',
      'store_error': 'Ссылка для загрузки не настроена или не открывается. Повторите попытку позже.',
      'badge': 'Обязательное обновление',
    },
  };

  Map<String, String> get _copy {
    final language = (Get.locale?.languageCode ??
            Get.deviceLocale?.languageCode ??
            'fr')
        .toLowerCase();
    return _translations[language] ?? _translations['fr']!;
  }

  @override
  Widget build(BuildContext context) {
    final config = Get.find<AppConfigService>();
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final copy = _copy;
    final customMessage = config.updateMessage.value.trim();
    final message = customMessage.isNotEmpty ? customMessage : copy['message']!;

    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.system_update_alt_rounded,
                            size: 16, color: colors.onPrimaryContainer),
                        const SizedBox(width: 8),
                        Text(
                          copy['badge']!,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: colors.onPrimaryContainer,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: 300,
                    height: 270,
                    child: Lottie.asset(
                      'assets/lotties/Under Maintenance.json',
                      fit: BoxFit.contain,
                      repeat: true,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    copy['title']!,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: colors.onSurface,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    message,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: colors.onSurfaceVariant,
                      height: 1.55,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerHighest.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.verified_rounded,
                            size: 18, color: colors.primary),
                        const SizedBox(width: 9),
                        Text(
                          '${copy['version']}: ${config.currentServerVersion.value}',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: colors.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  TextButton(
                    onPressed: () => _openStore(config, copy),
                    style: TextButton.styleFrom(
                      foregroundColor: colors.primary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      textStyle: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(copy['button']!),
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_forward_rounded, size: 20),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Scrole',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colors.onSurfaceVariant.withValues(alpha: 0.7),
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openStore(
    AppConfigService config,
    Map<String, String> copy,
  ) async {
    final rawUrl =
        Platform.isIOS ? config.iosStoreUrl.value : config.androidStoreUrl.value;
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null ||
        !const {'https', 'http'}.contains(uri.scheme.toLowerCase())) {
      Get.snackbar(
        copy['store_error_title']!,
        copy['store_error']!,
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) {
        Get.snackbar(
          copy['store_error_title']!,
          copy['store_error']!,
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    } catch (_) {
      Get.snackbar(
        copy['store_error_title']!,
        copy['store_error']!,
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }
}
