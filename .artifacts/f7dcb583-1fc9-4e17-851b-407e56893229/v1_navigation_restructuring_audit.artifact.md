# Audit Navigation V1 — Restructuration Principale

## 1. État Actuel Analysé
- **`MainLayoutPage`** (`main_navigation_screen.dart`) : Utilise une `LazyIndexedStack` avec 3 onglets (Événements, Découvrir, Messagerie) et une `CustomBottomNav`.
- **`CustomBottomNav`** (`buton_nav.dart`) : Barre de navigation flottante en bas avec 4 boutons d'onglets et un bouton `+` ouvrant l'ancien `ExpandableAddMenu`.
- **`CustomAppBar`** (`main_app_bar.dart`) : Affiche l'avatar (qui appelait `goToProfilScreen`) et les boutons Chat et Notifications.

## 2. Décisions V1
1. **Suppression de la Bottom Navigation** : Remplacement de la structure par `EventScreen()` en tant que vue principale directe.
2. **Avatar → Drawer** : Taper sur l'avatar dans l'AppBar ouvre un `Drawer` latéral contenant les infos du profil et le lien "Mon profil".
3. **AppBar Actions** : Intégration de 3 boutons à droite : **Recherche** (`🔍`), **Notifications** (`🔔`), et **Messagerie** (`💬`).
4. **Recherche** : L'icône de recherche ouvre la page `SearchScreen` (`discover_screen.dart`).
5. **Floating Action Button (FAB)** : Ajout d'un FAB flottant `+` sur la page principale ouvrant un menu de création pour **Événement** et **Activité**.

## 3. Fichiers concernés
- **Modifiés** :
  - `lib/modules/module_principale/interne/pages/main_navigation_screen.dart`
  - `lib/modules/module_principale/interne/widgets/main_app_bar.dart`
  - `lib/modules/module_principale/interne/controllers/main_layout_controller.dart`
- **Supprimés** :
  - `lib/modules/module_principale/interne/widgets/buton_nav.dart`
  - `lib/modules/module_principale/interne/widgets/boutton_expand.dart`
