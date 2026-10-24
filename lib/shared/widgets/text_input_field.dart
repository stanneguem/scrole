import 'package:flutter/material.dart';

import '../../app/theme/text_styles.dart';

/// Champ de saisie du pseudo (username).
class TextInputField extends StatelessWidget {
  final TextEditingController controller;
  final String imputTitle;
  final String impuHintText;
  final Icon imputIcon;
  final FormFieldValidator<String> func;
  final int maxLines;
  final bool readOnly;
  final bool? enabled;

  const TextInputField({
    super.key,
    required this.controller,
    required this.imputTitle,
    required this.imputIcon,
    required this.impuHintText,
    required this.func,
    this.maxLines = 1,
    this.readOnly = false,
    this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      readOnly: readOnly,
      enabled: enabled,
      textInputAction: maxLines > 1 ? TextInputAction.newline : TextInputAction.next,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: imputTitle,
        hintText: impuHintText,
        prefixIcon: Padding(
          padding: EdgeInsets.only(bottom: maxLines > 1 ? (maxLines * 12.0) : 0),
          child: imputIcon,
        ),
        alignLabelWithHint: maxLines > 1,
        border: const OutlineInputBorder(),
        labelStyle: AppTextStyles.labelLarge,
        hintStyle: AppTextStyles.labelLarge,
      ),
      validator: func,
      autovalidateMode: AutovalidateMode.onUserInteraction,
    );
  }
}
