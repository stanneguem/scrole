# Rapport d'Audit — Intégration des Sondages dans le Feed et la PostCard

## A. Post Model
- **Fichier** : `lib/modules/module_communautes/centre/models/community_post.dart`
- **Classes** : `CommunityPost`, `CommunityPoll`, `PollOption`.
- **Poll présent** : Oui (`CommunityPoll? poll`).
- **Parsing** : `CommunityPoll.fromJson` désérialise correctement `kind`, `ends_at`, `is_closed`, `voters_count`, `has_voted`, `my_option_ids`, `results_visible`, `options`, `correct_option_id`, et `explanation`.

## B. Feed
- Chemin exact :
  `Supabase get_community_feed()` → Réponse JSON (contenant `poll` et `media`) → `CommunityPost.fromJson` (Model) → Repository → Controller (`CommunityFeedController`) → UI (`FeedPostCard`).

## C. PostCard
- **Fichier** : `lib/modules/module_communautes/interne/widgets/community/feed_post_card.dart`
- **Widget** : `FeedPostCard`
- **Structure** : Auteur → Contenu/Texte → Hashtags → Zone Médias (`PostMediaSlider`) → Zone Sondage (`PollCardWidget`) → Barre d'actions.

## D. Media
- `media` (`List<PostMedia>`) et `poll` (`CommunityPoll?`) coexistent parfaitement dans `CommunityPost`. Un post peut contenir à la fois du texte, des médias mixtes (photos/vidéos Bunny) et un sondage.

## E. Poll actuel
- Une implémentation frontend complète existe déjà : `PollCardWidget` (`lib/modules/module_communautes/interne/widgets/community/poll_card_widget.dart`), supportant les quatre types (`single`, `multiple`, `quiz`, `this_or_that`).

## F. Vote
- Intégré via `PollCardWidget` appelant `widget.controller.votePoll(widget.postId, _selectedOptionIds)`.

## G. Refresh
- Géré par `CommunityFeedController`, mettant à jour l'état du post après le vote.

## H. Cache
- Les posts sont gérés par le DAO local et le state management du feed.

## I. Problèmes trouvés
- Aucun problème structurel majeur n'a été trouvé. Le modèle et le widget de sondage (`PollCardWidget`) sont déjà en place et fonctionnels.

## J. Proposition d'architecture
- Le système actuel est déjà pleinement en mesure d'afficher et de voter sur les sondages (`single`, `multiple`, `quiz`, `this_or_that`) lorsqu'un post possède le champ `poll` renvoyé par `get_community_feed()`.

## K. Fichiers à modifier
- Aucun fichier ne nécessite de modification urgente pour l'affichage de base des sondages, puisque le modèle, `FeedPostCard` et `PollCardWidget` sont déjà connectés.
