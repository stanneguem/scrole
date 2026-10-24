# Implementation Plan - V1 Scrole: Removal of Communities Module

Retirer entièrement le module Communautés du frontend pour la V1, en centrant l'application sur les Événements, la Messagerie et les Profils, sans altérer ces derniers.

## User Review Required

> [!IMPORTANT]
> Aucune table ni RPC Supabase ne sera modifiée ou supprimée (le backend est gelé). Seul le code frontend exposant ou utilisant les communautés est retiré.

## Proposed Changes

### Navigation & Layout
#### [MODIFY] [main_navigation_screen.dart](file:///home/gabriel/travail/scrole/scrole/lib/modules/module_principale/interne/pages/main_navigation_screen.dart)
- Retirer l'onglet `CommunityListScreen` de la `LazyIndexedStack`.
#### [MODIFY] [main_layout_controller.dart](file:///home/gabriel/travail/scrole/scrole/lib/modules/module_principale/interne/controllers/main_layout_controller.dart)
- Retirer l'initialisation de `CommunityListController` et la méthode `onCreateCommunity`.

### Routing
#### [MODIFY] [app_routes.dart](file:///home/gabriel/travail/scrole/scrole/lib/app/routes/app_routes.dart) & [app_pages.dart](file:///home/gabriel/travail/scrole/scrole/lib/app/routes/app_pages.dart)
- Retirer les routes et bindings liés au module Communautés.

### Module Removal
#### [DELETE] [module_communautes/](file:///home/gabriel/travail/scrole/scrole/lib/modules/module_communautes)
- Suppression complète du répertoire exclusif du module communautés.

## Verification Plan

### Automated Tests
- Run `/home/gabriel/develop/flutter/bin/flutter test`
- Run `/home/gabriel/develop/flutter/bin/flutter analyze`

### Manual Verification
- Vérifier l'absence de tout écran ou bouton "Communautés" dans l'application V1.
- Vérifier que les Événements et la Messagerie fonctionnent parfaitement.
