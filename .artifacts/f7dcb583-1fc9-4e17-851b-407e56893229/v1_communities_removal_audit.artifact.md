# Audit Préliminaire — Retrait du Module Communautés pour la V1

## Cartographie des Dépendances du Module Communautés

### 1. Composants Exclusifs au Module Communautés (Suppression Sûre)
- **Dossier complet** : `lib/modules/module_communautes/`
  - *Services* : `CommunityService`, `BunnyVideoService`, `CommunityOutboxProcessor`, `CommunityVideoManager`.
  - *Repositories* : `CommunityRepository`.
  - *Controllers* : `CommunityListController`, `CommunityFeedController`, `CommunityCreationController`, `CommunityManagementController`, `CommunityPreviewController`, `CommunityJoinRequestsController`, `CommunitySettingsController`.
  - *Pages / Screens* : `CommunityListScreen`, `CommunityFeedScreen`, `CommunityCreationScreen`, `CommunityPreviewScreen`, `CommunityRolesScreen`, `CreateCommunityPostScreen`, etc.
  - *Widgets* : `PollCardWidget`, `CreatePollSheet`, `PostMediaSlider`, `CommunityGridCards`, `CommunityHeader`, `CommunityCommentsSheet`, etc.
  - *Models* : `CommunityPost`, `CommunityPoll`, `CommunityModel`, `Community`, `CommunityMembership`, `CommunitySettings`, etc.

### 2. Points d'Intégration et Navigation (À Nettoyer / Rediriger)
- **`MainLayoutPage`** (`main_navigation_screen.dart`) :
  - Contient le 3ème onglet `CommunityListScreen()`.
  - *Action V1* : Remplacer l'onglet Communautés (ou ajuster les onglets V1 pour ne garder que Événements et Messagerie/Recherche selon le layout V1).
- **`MainLayoutController`** (`main_layout_controller.dart`) :
  - Importe et initialise `CommunityListController`.
  - *Action V1* : Retirer `CommunityListController` et la méthode `onCreateCommunity`.
- **Routes / AppPages** (`app_routes.dart` / `app_pages.dart`) :
  - Contiennent les routes `/community_list`, `/communities/:id`, etc.
  - *Action V1* : Retirer les routes et bindings du module communautés.

### 3. Références Partagées avec les Événements ou la Découverte (À Isoler / Maintenir)
- **`AppPages.communityDetailPath(id)` / Liens de redirection** :
  - Utilisé par `module_evenement` (`event_detail_page.dart`, `event_preview_screen.dart`) et `module_decouverte` pour rediriger vers une communauté depuis un événement ou une découverte.
  - *Action V1* : Comme les communautés sont hors périmètre V1, ces redirections vers des détails de communauté dans les événements doivent soit être désactivées (no-op), soit masquées, en veillant à ne pas casser le rendu des événements eux-mêmes.
- **Widgets partagés potentiels** :
  - `media_full_screen_page.dart`, `video_full_screen_viewer.dart`, `app_cached_image.dart` : Utilisés également dans la messagerie et les événements. **Conservés**.

## Plan d'Action pour l'Étape Suivante
1. Retirer `CommunityListScreen` de la navigation principale (`MainLayoutPage`).
2. Retirer l'enregistrement de `CommunityListController` dans `MainLayoutController`.
3. Supprimer le dossier `lib/modules/module_communautes/`.
4. Nettoyer les routes et les références de navigation orphelines (ex: boutons de création de communauté).
5. Vérifier la compilation, lancer `flutter analyze` et `flutter test`.
