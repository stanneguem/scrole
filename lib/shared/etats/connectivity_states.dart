/// États d'affichage de la bannière de connexion.
enum ConnectionBannerState {
  /// Rien à afficher (connecté, ou jamais eu de coupure).
  hidden,

  /// Hors ligne — bandeau rouge avec loader, reste affiché tant que
  /// [AppController.isConnected] est false.
  offline,

  /// Reconnexion détectée — bandeau vert "De nouveau en ligne" affiché
  /// brièvement avant de repasser à [hidden].
  backOnline,
}