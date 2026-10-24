# Audit du module Communautés — 24 octobre 2026

## Périmètre inspecté

- Création, aperçu, visibilité publique/privée et accès aux communautés.
- Adhésion immédiate ou sur approbation, demandes en attente, acceptation/refus.
- Rôles administrateur/modérateur/membre, gestion des membres et exclusions.
- Paramètres de publication, approbation des posts, commentaires, réactions et signalements.
- Signalements de publications/commentaires et de membres, file de modération, actions de résolution.
- Repartage vers le fil, une autre communauté, les commentaires partagés et les stories.
- Permissions Postgres/RLS et payloads utilisés par les flux de communauté et le fil global.

## Corrections réalisées

### Repartage des publications

- Le réglage de communauté `community_settings.allow_post_sharing` est disponible depuis les paramètres d’accès de la communauté, indépendamment de sa visibilité publique/privée.
- Le backend exige à la fois l’autorisation de repartage de la publication et celle de la communauté.
- Le même contrôle s’applique aux partages de commentaires et à chaque niveau d’une chaîne de republications.
- Les flux `get_home_feed` et `get_community_feed` renvoient le réglage effectif pour que l’interface puisse désactiver l’action avant l’envoi.
- Les cartes de publication combinent désormais le réglage individuel et celui de la communauté.

### Protection des sources partagées

- Les chaînes de republications sont vérifiées sur toute leur profondeur (limite défensive de 8 niveaux).
- Les aperçus conservés sont expurgés des identifiants de la source, des identifiants d’auteur, des références de communauté et des compteurs d’interaction.
- Les aperçus restreints ne proposent pas de repartage supplémentaire.
- Les instantanés sont expurgés à l’écriture et les politiques RLS des tables `community_posts` et `stories` empêchent la lecture directe des lignes partagées lorsque le lecteur ne peut pas ouvrir la source. Les RPC de flux peuvent encore retourner un aperçu expurgé. Un wrapper public très limité permet d’appliquer le contrôle RLS sans exposer le schéma privé.

### Signalements et modération

- Le menu d’une publication utilise désormais `report_content` au lieu d’afficher un faux message de succès.
- Les membres peuvent signaler un autre membre depuis la liste des membres et depuis le menu d’une publication communautaire.
- `report_community_member` vérifie l’adhésion du signalant, l’existence du membre, le motif actif, les limites de fréquence et le réglage `allow_reports`.
- Le réglage de signalement des publications/commentaires reste appliqué côté serveur.
- Le compteur du centre de modération utilise les vraies clés de réponse (`reports`, `join_requests`, `pending_posts`, `spam`) sans additionner les alertes agrégées, qui doublonneraient certains éléments.
- Une file dédiée aux publications suspectées de spam est maintenant accessible et utilise `moderate_community_post` pour approuver ou rejeter les contenus, ce qui met également à jour les indicateurs de spam.
- Les alertes automatiques sont visibles et conduisent vers la file d’action appropriée (signalements, spam, publications en attente ou demandes d’adhésion).
- Les libellés de signalement, de spam et d’alertes sont disponibles dans les neuf langues et couverts par des tests de traduction.

### Adhésions et rôles

- Les RPC de demande et de réponse aux adhésions ont été inspectées : critères d’accès, exclusion, statut en attente, insertion du membre lors de l’acceptation et notification du demandeur.
- Les écrans de demandes gèrent la pagination par curseur et l’état de chargement/erreur.
- Les libellés de prévisualisation et de demandes d’adhésion manquants ont été ajoutés dans les neuf catalogues de langue, avec un test de couverture.
- Les actions de résolution des signalements sont autorisées côté serveur selon le rôle communautaire; l’exclusion d’un membre reste réservée aux administrateurs.

## Migrations appliquées

- `community_repost_permissions_and_story_snapshots`
- `enforce_community_member_report_setting`
- `align_community_repost_availability`
- `include_repost_setting_in_feeds`
- `enforce_community_repost_setting_for_comment_shares`
- `disable_repost_on_restricted_snapshots`
- `secure_shared_source_metadata`
- `use_public_source_access_wrapper_in_rls`

## Validation restante

- Les colonnes, fonctions, droits d’exécution et politiques RLS ont été vérifiés sur Supabase.
- Des tests unitaires couvrent la combinaison du réglage de communauté et du réglage individuel de repartage.
- Les workflows GitHub de validation Flutter ont été ajoutés/corrigés. Il faut attendre leurs résultats sur le commit final.
- Il reste à effectuer un test fonctionnel avec deux comptes réels : un membre de la communauté source et un non-membre, en vérifiant le fil, le repartage dans une autre communauté, les stories, les signalements et les demandes d’adhésion.
