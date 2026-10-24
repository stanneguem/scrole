import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Bouton de validation du formulaire avec indicateur de chargement.
class CreateAccountButton extends StatelessWidget {
  const CreateAccountButton({
    super.key,
    required this.onPressed,
    this.isSubmitting = false,
  });

  final VoidCallback onPressed;
  final bool isSubmitting;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: isSubmitting ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.primary,
          foregroundColor: colors.onPrimary,
          disabledBackgroundColor: colors.primary.withOpacity(0.55),
          disabledForegroundColor: colors.onPrimary.withOpacity(0.8),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: isSubmitting
              ? SizedBox(
            key: const ValueKey('loading'),
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: colors.onPrimary,
            ),
          )
              : Text(
            'create_account_button'.tr,
            key: const ValueKey('text'),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}