# Scrole — migration complète des médias vers Cloudflare R2

## Objectif et invariants

- Tous les nouveaux fichiers image et vidéo téléversés par Scrole doivent être stockés dans Cloudflare R2 : avatars/couvertures utilisateur, avatars/couvertures de communautés, posts, Stories, commentaires, messagerie, événements, pièces jointes et captures de rapports si le produit les conserve.
- Supabase reste la source de vérité pour Auth, PostgreSQL, autorisations, métadonnées et références des objets.
- Ne supprimer aucun objet de Supabase Storage pendant les phases de migration.
- Garder la compatibilité de lecture des URL Supabase historiques jusqu'à la fin de la migration des données et des références.
- Ne pas exposer de clés R2 dans l'application Flutter. Les uploads sont autorisés par une Edge Function authentifiant l'utilisateur et générant une URL présignée de courte durée.
- Les médias privés ne doivent pas être servis publiquement sans contrôle d'accès explicite.

## Convention de clés R2

Les « dossiers » R2 sont des préfixes de clés d'objets, créés automatiquement par le nom de clé. Pas de création manuelle nécessaire.

- `profiles/{userId}/avatar/{uuid}.{ext}`
- `profiles/{userId}/cover/{uuid}.{ext}`
- `communities/{communityId}/avatar/{uuid}.{ext}`
- `communities/{communityId}/cover/{uuid}.{ext}`
- `posts/{postId}/{uuid}.{ext}`
- `stories/{storyId}/{uuid}.{ext}`
- `comments/{commentId}/{uuid}.{ext}`
- `messages/{conversationId}/{messageId}/{uuid}.{ext}`
- `events/{eventId}/cover/{uuid}.{ext}`
- `bug-reports/{userId}/{uuid}.{ext}`
- `temporary/{userId}/{uploadId}/{uuid}.{ext}` pour les uploads incomplets si nécessaire.

Les identifiants doivent être générés côté serveur. Les noms originaux de fichiers ne doivent pas servir de clé directe. L'Edge Function doit valider MIME, extension, taille, type de média, propriétaire/permissions et préfixe autorisé. La durée vidéo doit être validée à partir des métadonnées réelles côté serveur ou par un traitement de confiance, pas uniquement à partir d'une valeur fournie par le client.

## État constaté lors de l'audit initial

- `lib/app/repository_global/storage_repository.dart` envoie encore les fichiers vers Supabase Storage (`avatars`, `community-media`, `bug-reports`, `community-videos`) et fabrique des URL publiques Supabase.
- `supabase/functions/r2-media-upload/index.ts` existe, mais le flux inspecté n'autorise que les vidéos MP4/MOV et crée une URL présignée. Il ne couvre pas encore toutes les images et tous les parcours.
- La création de publication communautaire a déjà un flux mixte photos/vidéos partiellement adapté à R2; ce flux doit être consolidé avec le stockage générique plutôt que dupliqué.
- Les Stories, les profils, les communautés, les événements et la messagerie doivent être inspectés et migrés individuellement; ne pas supposer qu'ils utilisent tous le même dépôt.
- Les objets existants Supabase restent en place jusqu'à ce qu'une migration idempotente, vérifiable et réversible soit exécutée.

## Phases d'implémentation

1. **Inventaire et contrat commun** : repérer chaque appel à Storage, upload direct, Edge Function et URL de bucket; documenter les tables/champs qui stockent les références.
2. **API R2 centrale** : étendre l'Edge Function pour les images et vidéos avec une liste blanche de catégories, permissions par catégorie, limites de taille, MIME, clés préfixées, URLs présignées et erreurs explicites. Ajouter les secrets dans Supabase; ne jamais les committer.
3. **Client Flutter commun** : adapter le dépôt de stockage afin que tous les parcours image utilisent la même API R2 et la même convention de clés. Garder la suppression d'objets R2 séparée de la suppression des références DB.
4. **Migrer les parcours par lots** : profils et onboarding; communautés; événements; publications et commentaires; Stories; messagerie et pièces jointes; rapports et autres uploads.
5. **Lecture et cache** : accepter URL R2 et anciennes URL Supabase simultanément; vérifier miniatures, cache, viewer, partage, suppression et modes hors ligne.
6. **Inventaire historique** : inventorier les buckets Supabase et les colonnes/références. Migrer par lots avec reprise sur erreur, journal de correspondance ancien→nouveau, validation de taille/hash et mise à jour atomique des références.
7. **Vérification** : tests unitaires, analyse Flutter, tests Edge Function et essais manuels Android; vérifier upload/lecture/suppression pour chaque catégorie.
8. **Retrait différé** : désactiver les nouveaux uploads Supabase seulement lorsque tous les flux sont passés sur R2; supprimer les anciens objets uniquement après validation explicite, sauvegarde et période de rétention.

## Critères d'acceptation

- Aucun nouveau média image/vidéo ne part vers Supabase Storage.
- Aucun secret R2 n'est présent dans Flutter ou Git.
- Les permissions sont vérifiées côté serveur, notamment communautés privées et conversations.
- Les anciennes URL continuent de fonctionner pendant la migration.
- Un échec d'upload ne crée pas de référence DB cassée; un échec DB après upload déclenche une compensation ou un nettoyage différé.
- Les tests couvrent chaque parcours et l'ordre des médias multiples est conservé.
