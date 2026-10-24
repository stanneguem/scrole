import 'package:flutter/material.dart';

/// Bouton d'authentification réutilisable (Google, Apple, téléphone, email...).
///
/// - Radius fixe : 10px
/// - Prend un [onPressed], un [icon] optionnel et un [text] obligatoire
/// - Par défaut, va chercher ses couleurs dans le [ColorScheme] du thème
///   courant (issu de `AppTheme.lightTheme` / `AppTheme.darkTheme`), donc
///   il s'adapte automatiquement au light/dark mode sans rien importer.
/// - [backgroundColor] / [textColor] / [borderColor] permettent d'override
///   ponctuellement (ex: bouton Apple toujours noir/blanc, quel que soit
///   le thème).
class AppAuthButton extends StatelessWidget {
  const AppAuthButton({
    super.key,
    required this.onPressed,
    required this.text,
    this.icon,
    this.backgroundColor,
    this.textColor,
    this.borderColor,
    this.isLoading = false,
  });

  /// Callback déclenché au tap. Ignoré si [isLoading] est true.
  final VoidCallback onPressed;

  /// Libellé du bouton (ex: "Continue with Google").
  final String text;

  /// Icône affichée à gauche du texte. Optionnelle — si null, le texte
  /// est simplement centré seul.
  final Widget? icon;

  /// Couleur de fond. Si null → `colorScheme.surface`.
  final Color? backgroundColor;

  /// Couleur du texte (et de l'icône si elle hérite de currentColor).
  /// Si null → `colorScheme.onSurface`.
  final Color? textColor;

  /// Couleur de bordure. Si null → `colorScheme.outline`.
  /// Passe `Colors.transparent` explicitement si tu ne veux pas de bordure.
  final Color? borderColor;

  /// Affiche un spinner à la place du contenu et désactive le tap.
  final bool isLoading;

  static const double _radius = 10;
  static const double _height = 52;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final Color bg = backgroundColor ?? colorScheme.surface;
    final Color fg = textColor ?? colorScheme.onSurface;
    final Color border = borderColor ?? colorScheme.outline;

    return SizedBox(
      width: double.infinity,
      height: _height,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(_radius),
        child: InkWell(
          onTap: isLoading ? null : onPressed,
          borderRadius: BorderRadius.circular(_radius),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(_radius),
              border: Border.all(color: border, width: 1),
            ),
            alignment: Alignment.center,
            child: isLoading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(fg),
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (icon != null) ...[icon!, const SizedBox(width: 10)],
                      Text(
                        text,
                        style: TextStyle(
                          color: fg,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
