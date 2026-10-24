# Rapport d'Audit — Comportement de PollCardWidget vs Contrat Backend

## A. Correspondance backend/frontend (`CommunityPoll`)

| Champ backend | Présent dans modèle (`CommunityPoll`) | Utilisé par `PollCardWidget` | Comportement |
| :--- | :--- | :--- | :--- |
| `kind` | Oui (`kind`) | Oui | Distingue `single`, `multiple`, `quiz`, `this_or_that`. |
| `allow_multiple` | Non explicitement (déduit de `kind == 'multiple'`) | Non | Géré par `kind == 'multiple'`. |
| `ends_at` | Oui (`endsAt`) | Non | Parsé dans le modèle mais non affiché. |
| `is_closed` | Oui (`isClosed`) | Oui | Désactive les interactions si `true`. |
| `voters_count` | Oui (`votersCount`) | Oui | Affiche le nombre de votants. |
| `has_voted` | Oui (`hasVoted`) | Oui | Gère l'état de vote (notamment pour les quiz). |
| `my_option_ids` | Oui (`myOptionIds`) | Oui | Initialise et met à jour `_selectedOptionIds`. |
| `results_visible`| Oui (`resultsVisible`) | Oui | Détermine si les pourcentages/votes sont affichés. |
| `correct_option_id`| Non explicitement (`PollOption.isCorrect`) | Oui | Identifie la bonne réponse pour les quiz (`option.isCorrect == true`). |
| `explanation` | Oui (`explanation`) | Oui | Affiche l'explication du quiz si présente. |

## B. `single`
- **Comportement actuel** : Une seule option sélectionnable (via `Radio`). Au clic, appelle immédiatement `controller.votePoll`. Affiche les pourcentages si `resultsVisible || hasVoted || isClosed`.

## C. `multiple`
- **Comportement actuel** : Plusieurs options sélectionnables (via `Checkbox`). Envoie la liste des `_selectedOptionIds` au contrôleur.

## D. `quiz`
- **Comportement actuel** : Réponse unique. Une fois voté (`hasVoted`), les options affichent des couleurs distinctives (vert pour correct, rouge pour faux si sélectionné) et l'explication (`explanation`) est affichée.

## E. `this_or_that`
- **Comportement actuel** : Traité comme un sondage `single` (sélection unique d'une option).

## F. Résultats
- Utilise `option.percent` et `option.votes` fournis par le backend lorsque `resultsVisible || hasVoted || isClosed` est vrai. Le frontend ne calcule pas les statistiques lui-même.

## G. Fermeture
- `isClosed` désactive les interactions de vote. `ends_at` est présent dans le modèle mais non affiché explicitement sous forme de compte à rebours.

## H. Vote
- **Flux exact** :
  `PollCardWidget` (tap option) → `CommunityFeedController.votePoll()` → `CommunityService.voteCommunityPoll()` → RPC backend → Retourne le nouveau `poll` → `CommunityPost.copyWith(poll: updatedPoll)` → `PollCardWidget` reconstruit.

## I. Problèmes UX/UI constatés
- Aucun dysfonctionnement bloquant. L'affichage et la logique des 4 types de sondages sont pleinement cohérents avec le contrat backend.

## J. Corrections recommandées
- Aucune modification requise pour l'instant. Le système est prêt et conforme au contrat backend.
