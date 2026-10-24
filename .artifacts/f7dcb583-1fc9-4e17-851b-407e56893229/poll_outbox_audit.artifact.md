# Rapport d'Audit — Intégration de l'Outbox et du Debounce (5s) pour les Votes de Sondage

## A. Où le clic sur une option est traité
- **Fichier** : `lib/modules/module_communautes/interne/widgets/community/poll_card_widget.dart`
- **Méthode** : `_onOptionTap(PollOption option)`

## B. Où `selectedOptionIds` est stocké
- Stocké localement dans l'état du widget stateful `_PollCardWidgetState` (`_selectedOptionIds`).

## C. Comment `votePoll()` fonctionne actuellement
- **Fichier** : `lib/modules/module_communautes/interne/controllers/community/community_feed_controller.dart`
- **Méthode** : `votePoll(String postId, List<String> optionIds)`
- **Fonctionnement actuel** : Appelle immédiatement `_service.voteCommunityPoll` de manière synchrone/directe au réseau.

## D. Où l'appel `vote_community_poll` est effectué
- **Service** : `CommunityService.voteCommunityPoll` (`lib/modules/module_communautes/centre/services/community_service.dart`)
- **Repository** : `CommunityRepository.voteCommunityPoll` (`lib/modules/module_communautes/externe/repositories/community_repository.dart`) invoquant le RPC Supabase `vote_community_poll`.

## E. Quelle Outbox existe déjà
- **Service** : `CommunityOutboxProcessor` (`lib/modules/module_communautes/centre/services/community_outbox_processor.dart`)
- **Stockage** : Table `community_outbox` gérée par `CommunityLocalDao`.

## F. Comment les autres opérations utilisent cette Outbox
- Via `enqueueReactionWithCoalescing` (pour les réactions de posts avec un debounce de 5 secondes) et `create_post`.

## G. Comment le retry fonctionne
- Géré par `CommunityOutboxProcessor` avec un backoff exponentiel (5s, 15s, 30s, 2min) et classification des erreurs terminales (`_isTerminalError`).

## H. Comment le cache SQLite est mis à jour
- Via `CommunityLocalDao` et les transactions locales de cache de communauté.

## I. Comment `CommunityPost` est rafraîchi après une mutation
- Actuellement, après un vote réussi, `CommunityFeedController.votePoll` met à jour directement l'élément dans la liste réactive `posts` avec le nouveau `poll` retourné par le serveur (`post.copyWith(poll: updatedPoll)`).

## J. Où implémenter le debounce de 5 secondes sans créer une deuxième architecture
- Ajouter une méthode `enqueuePollVoteWithCoalescing` dans `CommunityOutboxProcessor` (similaire à `enqueueReactionWithCoalescing`), en utilisant un dictionnaire de debouncers basé sur `postId` et `userId`. Le traitement s'exécutera via `processPendingOperations` en appelant la RPC `vote_community_poll`.
