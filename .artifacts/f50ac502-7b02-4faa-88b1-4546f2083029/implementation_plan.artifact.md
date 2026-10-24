# Plan d'Implémentation : Identité Uniforme, Commentaires Interactifs, Visionneuse, Fils Communautaires et Partage en Story

Ce plan détaille la stratégie d'implémentation pour les 8 parties demandées, en respectant l'architecture Flutter existante (GetX, outbox, design system, local cache) sans modifier le backend Supabase.

## User Review Required

> [!NOTE]
> Aucun changement backend (tables, RPC, RLS) n'est requis ; toutes les fonctions RPC mentionnées (`set_comment_reaction`, `share_comment`, `get_comment_thread`, `get_community_feed`, `get_communities_feed`, `share_post_to_story`, etc.) sont déjà prêtes et testées côté serveur.

## Open Questions

- Aucun point bloquant identifié. Les composants de base (badges, gestion des commentaires, visionneuse, outbox) sont déjà en place et seront étendus.

## Proposed Changes

### 1. Composant d'Identité Unifié (`UserIdentityRow`)
- [NEW] `lib/shared/widgets/user_identity_row.dart` : Widget réutilisable affichant Avatar, Nom (`first_name` + `last_name`), Pseudo (`@username`), et Badge de certification (`UserCertifiedBadge`) si `is_certified == true`.
- Intégration de `UserIdentityRow` dans :
  - `FeedPostCard` / `_RepublicationPostCard` (republication, original incrusté, posts normaux).
  - `CommunityCommentsSheet` (commentaires, réponses).
  - `StoryViewerScreen` et `_StoryViewersSheet` (stories et liste des vues).

### 2. Encart de l'Original en Lecture Seule
- Mise à jour du pied de l'encart d'original dans `_RepublicationPostCard` pour afficher la barre complète de statistiques (Likes, Dislikes, Vues, Commentaires, Partages) en lecture seule avec les icônes officielles de l'app.

### 3. Réactions et Partage de Commentaires
- `HomeFeedRepository` & `CommunityCommentsSheet` :
  - Implémentation de `set_comment_reaction` pour les likes/dislikes sur les commentaires.
  - Implémentation du partage de commentaire via `share_comment` (générant un post de type `shared_comment`).
  - Gestion des threads de commentaires (`get_comment_thread`).

### 4. Visionneuse d'Images Plein Écran (`MediaFullScreenPage`)
- Intégration de la récupération des vraies statistiques du post via `get_post_counters`.
- Ajout des boutons actifs 👍 👎 (réactions), 🔁 (partage), et 💬 (commentaires) synchronisés avec le post en arrière-plan.

### 5. Fil d'Actualité d'une Communauté (`CommunityFeedScreen` / `CommunityFeedController`)
- Connexion complète avec `get_community_feed`, gestion de l'en-tête, du composeur conditionnel selon les droits (`posts_require_approval`), de la liste des publications en attente de validation (`get_my_community_posts`), et du panneau de modération pour les admins (`get_community_pending_posts`, `moderate_community_post`).

### 6. Fil des Communautés (`CommunitiesFeedScreen` / Onglet dédié)
- Création/Amélioration de l'écran global des communautés (`get_communities_feed`) avec barre de filtres horizontale ("Toutes" + pastilles de chaque communauté confirmée), affichage de la communauté d'origine sur chaque post et pagination.

### 7. Partage de Post en Story (`CreateStoryScreen` & `StoryViewerScreen`)
- Ajout de la 4ème option "Ajouter à ma story" dans `_ShareSheetWidget` (`share_post_to_story`).
- Affichage dans le lecteur de stories des stories de type 'post' (`kind = 'post'` avec `shared_post`).

## Verification Plan

### Automated Tests
- Exécution des tests unitaires et d'intégration existants (`flutter test`).

### Manual Verification
- Vérification visuelle sur l'application des badges uniformes, de l'encart original, des réactions aux commentaires, de la visionneuse avec vraies stats, des fils communautaires et du partage en story.
