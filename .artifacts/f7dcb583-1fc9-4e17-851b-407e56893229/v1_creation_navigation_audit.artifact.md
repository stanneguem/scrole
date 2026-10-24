# Audit — Migration du FAB de Création vers le Drawer et Page Dédiée

## Réponses à l'audit (Étape 7)
1. **Où est déclaré le Drawer ?** Dans `MainLayoutPage` (`lib/modules/module_principale/interne/pages/main_navigation_screen.dart`).
2. **Où est déclaré le FAB actuel ?** Dans `MainLayoutPage` (`main_navigation_screen.dart`).
3. **Quelle page est actuellement ouverte depuis le FAB ?** Un bottom sheet (`_showCreationMenu`).
4. **Quelle route est utilisée pour créer un événement ?** `AppPages.createEvent`.
5. **Quelle route est utilisée pour créer une activité ?** `AppPages.createactivite`.
6. **Quels controllers/bindings sont nécessaires ?** Les bindings et contrôleurs existants (`CreateEventBinding`, `CreateActiviteBinding`).
7. **Existe-t-il déjà une page de sélection similaire ?** Non, création de `CreationSelectionScreen`.
8. **Où sont déclarées les routes GetX ?** `AppRoutes` (`app_routes.dart`) / `AppPages` (`app_pages.dart`).
9. **Où le Drawer est-il construit ?** Dans `MainLayoutPage` (`main_navigation_screen.dart`).
10. **Quels tests doivent être adaptés ?** Tests de navigation principaux.
