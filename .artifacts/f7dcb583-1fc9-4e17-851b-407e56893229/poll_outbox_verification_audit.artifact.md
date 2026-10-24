# Rapport d'Audit — Vérification de l'Outbox et du Debounce (5s) pour les Votes de Sondage

## A. Architecture réelle
Clic utilisateur (`PollCardWidget._onOptionTap`) → Modification locale de l'état `_selectedOptionIds` avec `setState()` → Appel simultané à `widget.controller.votePoll()` (appel réseau immédiat) et `outboxProcessor.enqueuePollVoteWithCoalescing()` (Outbox différée 5s).

## B. Debounce
- **Durée** : 5 secondes.
- **Emplacement** : `CommunityOutboxProcessor._pollVoteDebouncers`.
- **Fonctionnement** : Chaque tap annule le timer précédent pour le même post/utilisateur et en redémarre un de 5 secondes.
- **État actuel** : Non conforme en pratique car l'appel immédiat `widget.controller.votePoll()` est exécuté en parallèle du debounce.

## C. Outbox
- **Type d'opération** : `poll_vote`
- **Payload** : `{'option_ids': [...]}` (peut être `[]`)
- **Table** : `community_outbox`
- **DAO** : `CommunityLocalDao`
- **Processor** : `CommunityOutboxProcessor.processPendingOperations()`

## D. Coalescing
- **Clé** : `poll_vote_${postId}_$userId`
- **Comportement** : Remplace l'ancien timer et nettoie les opérations en attente dans la base locale (`deletePendingOperationByTypeAndPost`) pour ne persister que le dernier état au bout de 5 secondes.
- **Isolation utilisateur** : Assurée par `userId` et `postId`.

## E. `option_ids = []`
- Le retrait complet des options (pour `multiple`) produit `[]` et est correctement persisté dans le payload Outbox.

## F. Single
- Conforme localement (`_selectedOptionIds = [option.id]`).

## G. Multiple
- Conforme localement (ajout/suppression dans la liste, supportant `[]`).

## H. This or That
- Conforme localement (choix unique).

## I. Quiz
- Conforme localement avant synchronisation.

## J. Offline
- L'Outbox gère l'enregistrement local hors-ligne si le réseau est absent.

## K. Retry
- Réutilise le mécanisme de backoff exponentiel (5s, 15s, 30s, 2min) et `_isTerminalError`.

## L. Cache / UI
- Après succès du processor, met à jour `CommunityPost.poll` via `CommunityFeedController`.

## M. Risques (Problèmes trouvés)
1. **Anomalie critique** : Dans `PollCardWidget._onOptionTap`, l'appel direct `widget.controller.votePoll(widget.postId, _selectedOptionIds)` est toujours présent juste avant le bloc d'appel à l'Outbox. Cela déclenche un appel réseau immédiat non souhaité.

## N. Verdict final
⚠️ **PARTIELLEMENT CONFORME — corrections précises nécessaires**

### Corrections recommandées (à ne pas appliquer pour l'instant) :
1. **Fichier** : `lib/modules/module_communautes/interne/widgets/community/poll_card_widget.dart`
2. **Méthode** : `_onOptionTap`
3. **Problème** : Appel direct redondant et immédiat à `widget.controller.votePoll(...)`.
4. **Comportement actuel** : Envoi réseau immédiat + Outbox 5s.
5. **Comportement attendu** : Mise à jour locale immédiate (`setState`) + enregistrement Outbox exclusif avec debounce de 5s (aucun appel réseau immédiat).
6. **Correction minimale proposée** : Supprimer la ligne `widget.controller.votePoll(widget.postId, _selectedOptionIds);` de `_onOptionTap`.
