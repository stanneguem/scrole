# Diagnostic : Paramètres et règles d'une communauté

## 1. Composants existants identifiés
- **Écran des paramètres globaux** : `CommunitySettingsScreen` (`community_settings_screen.dart`) gère actuellement la liste des options (Membres, Membres exclus, Signalement, Quitter la communauté) mais redirigeait "Paramètres & Règles" vers une simple Snackbar.
- **Gestion des membres** : `CommunityMembersScreen` (`community_members_screen.dart`) gère l'affichage des membres, recherche, rôles (admin, moderateur, membre) et actions de modération.
- **Membres exclus** : `ExcludedMembersScreen` (`excluded_members_screen.dart`) gère les exclusions.
- **Repository** : `CommunityRepository` (`community_repository.dart`) centralise les appels RPC Supabase (`create_community`, `get_my_communities`, `leave_community`, `get_community_members`, `update_community_member_role`, `exclude_community_member`, etc.).
- **Service** : `CommunityService` (`community_service.dart`) gère le cache local SQLite (`CommunityLocalDao`), la synchronisation et les appels repository.

## 2. Fonctions RPC Supabase à intégrer
- **Accès et confidentialité** : `get_community_access_rules`, `update_community_access_rules`, `update_community_settings`.
- **Règles** : `set_community_rule`, `delete_community_rule`.
- **Publications et interactions** : `update_community_post_settings`, `update_community_features`.
- **Informations et actions sensibles** : `update_community_info`, `transfer_community_ownership`, `delete_community`.

## 3. Stratégie d'implémentation
1. Étendre `CommunityRepository` avec les méthodes RPC manquantes.
2. Étendre `CommunityService` pour exposer ces opérations.
3. Créer un écran complet `CommunitySettingsMainScreen` (`community_settings_main_screen.dart`) accessible depuis `CommunitySettingsScreen`.
4. Ajouter les traductions requises dans les 9 langues.
