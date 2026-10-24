import 'package:flutter/material.dart';
import 'package:get/get_utils/src/extensions/internacionalization.dart';
import '../../../../shared/constantes/image_path.dart';
import '../../../../shared/widgets/responsive_check.dart';

class SplashScreenView extends StatelessWidget {
  const SplashScreenView({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colors.surface,
      body: ResponsiveCheck(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(),

              const SizedBox(),
              const SizedBox(),
              const SizedBox(),
              const SizedBox(),
              const SizedBox(),
              const SizedBox(),

              // Logo
              SizedBox(
                height: 250,
                width: double.infinity,
                child: Image.asset(
                  ImagePath.logoApp,
                  fit: BoxFit.contain,
                ),
              ),

              const SizedBox(height: 20),
              const SizedBox(),
              const SizedBox(),

              // Loading
              SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: colors.primary,
                ),
              ),

              const SizedBox(height: 20),

              // Powered by
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "powered_by".tr,
                    style: TextStyle(
                      color: colors.onSurface,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    "M-APS",
                    style: TextStyle(
                      color: colors.onSurface,
                    ),
                  ),
                ],
              ),

              const SizedBox(),
            ],
          ),
        ),
      ),
    );
  }
}