import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../app/theme/text_styles.dart';
import '../../../../shared/constantes/image_path.dart';
import '../../../../shared/widgets/auth_button.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../interne/controllers/auth_controller.dart';

class AuthScreen extends GetView<AuthController> {
  const AuthScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Stack(
        children: [
          // Blobs
          Positioned(
            top: -80,
            left: -60,
            child: _AmbientBlob(color: colorScheme.primary, size: 260),
          ),
          Positioned(
            bottom: -100,
            right: -80,
            child: _AmbientBlob(color: colorScheme.secondary, size: 300),
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const Spacer(flex: 3),

                  // Logo
                  Container(
                    width: 156,
                    height: 156,
                    alignment: Alignment.center,
                    child: Image.asset(ImagePath.logoApp),
                  ),

                  const SizedBox(height: 28),

                  Text(
                    'welcome_back'.tr,
                    style: AppTextStyles.appName.copyWith(
                      color: colorScheme.onSurface,
                    ),
                  ),

                  const SizedBox(height: 12),

                  Text(
                    'description'.tr,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodyLarge.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),

                  const Spacer(flex: 4),

                  // Bouton Google
                  Obx(() => AppAuthButton(
                    onPressed: controller.authentification,
                    isLoading: controller.isLoading.value,
                    icon: SvgPicture.asset(
                      ImagePath.googleImage,
                      width: 20,
                      height: 20,
                      errorBuilder: (context, error, stackTrace) => Icon(
                        Icons.g_mobiledata_rounded,
                        color: colorScheme.onSurface,
                        size: 24,
                      ),
                    ),
                    text: 'continue_with_google'.tr,
                  )),

                  const SizedBox(height: 20),

                  Text.rich(
                    TextSpan(
                      style: AppTextStyles.link.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                      children: [
                        TextSpan(text: '${'agree_continue'.tr} '),
                        TextSpan(
                          text: 'terms'.tr,
                          style: AppTextStyles.link.copyWith(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.underline,
                          ),
                          recognizer: TapGestureRecognizer()
                            ..onTap = () => Get.toNamed('/terms'),
                        ),
                        TextSpan(text: ' ${'and'.tr} '),
                        TextSpan(
                          text: 'privacy_policy'.tr,
                          style: AppTextStyles.link.copyWith(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.underline,
                          ),
                          recognizer: TapGestureRecognizer()
                            ..onTap = () => Get.toNamed('/privacy-policy'),
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AmbientBlob extends StatelessWidget {
  const _AmbientBlob({required this.color, required this.size});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withValues(alpha: .12),
            color.withValues(alpha: 0),
          ],
        ),
      ),
    );
  }
}