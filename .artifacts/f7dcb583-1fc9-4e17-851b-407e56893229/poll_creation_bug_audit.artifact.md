# Rapport d'Audit — Échec de la Création des Sondages depuis Flutter

## A. Chemin exact de création Flutter
1. `CreateCommunityPostScreen` appelle `CommunityPollComposerScreen`.
2. `CommunityPollComposerScreen` génère un `pollMap`.
3. `CreateCommunityPostScreen` transmet ce `poll` à `CommunityFeedController.createPost()`.
4. `CommunityFeedController` appelle `CommunityService.createCommunityPost(poll: poll)`.
5. `CommunityService` appelle `CommunityRepository.createCommunityPost(poll: poll)`.
6. Le repository appelle la RPC Supabase `create_community_post(p_poll: poll)`.

## B. Payload `p_poll` réellement construit
Pour les types `single`, `multiple`, et `this_or_that`, le frontend construisait :
```json
{
  "kind": "single",
  "options": ["Option A", "Option B"],
  "duration_hours": 24
}
```

## C. Payload réellement envoyé au RPC
Le même dictionnaire avec `options` sous forme de tableau de `String`.

## D. Réponse du RPC
Le post (`community_posts`) est créé avec succès, mais la table `community_polls` et `community_poll_options` ne reçoivent aucun enregistrement car le traitement PL/pgSQL / JSONB du backend échoue ou ignore le tableau de chaînes brutes.

## E. Endroit exact où le sondage est perdu
Dans `CommunityPollComposerScreen` (`lib/modules/module_communautes/interne/pages/community/community_poll_composer_screen.dart`), où `options` est assigné à `texts` (`List<String>`) au lieu d'objets `{'label': ...}`.

## F. Cause racine probable
Divergence de format de données pour le champ `options` dans `p_poll` : le backend attend un tableau d'objets JSON contenant `label` (ex: `[{"label": "Option A"}]`), tandis que le frontend envoyait un tableau de chaînes de caractères (`["Option A"]`) pour `single`, `multiple`, et `this_or_that`.

## G. Fichiers concernés
- `lib/modules/module_communautes/interne/pages/community/community_poll_composer_screen.dart`

## H. Correction minimale proposée
Uniformiser la mise en forme de `formattedOptions` pour tous les types de sondages (`single`, `multiple`, `quiz`, `this_or_that`) afin qu'ils envoient tous un tableau d'objets contenant au minimum la clé `label` :
```dart
formattedOptions = texts.map((t) => {'label': t}).toList();
```
Et pour le quiz, y ajouter `'is_correct'`.
