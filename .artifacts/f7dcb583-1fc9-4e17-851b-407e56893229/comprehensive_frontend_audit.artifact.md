# Rapport d'Audit Technique — Frontend Scrole (Communautés, Médias, Compression, Bunny Stream & Suppression)

## A. Verdict global
- ⚠️ **PRÊT AVEC LIMITATIONS**

## B. Résumé
L'audit technique du code source révèle que le pipeline de compression locale, d'upload des photos sur Supabase Storage, de génération des miniatures, de création des posts et de suppression définitive via l'Edge Function `delete-community-post` est correctement implémenté et conforme aux contrats backend. Cependant, la reprise TUS après une fermeture complète ou un redémarrage de l'application est **partielle** (les états TUS et les sessions d'upload en cours ne sont pas persistés en base locale SQLite/Hive, ce qui conduit à la création d'un nouveau `video_id` en cas de redémarrage complet pendant un upload).

## C. Fonctionnalités vérifiées

| Fonctionnalité | Statut | Preuve / Fichier |
| :--- | :--- | :--- |
| **Compression image** | PASS | `CommunityService._compressImage` (`flutter_image_compress`) |
| **Compression vidéo** | PASS | `CommunityService.createCommunityPost` (`video_compress`) |
| **Bunny Stream** | PASS | `BunnyVideoService.requestUploadSession` (`bunny-video-upload`) |
| **TUS Upload** | PASS | `BunnyVideoService.uploadVideoTus` (Requêtes POST/PATCH TUS) |
| **Reprise après crash** | PARTIEL | En mémoire (mais perte de l'offset TUS et du `videoId` si l'app est fermée) |
| **Ordre media[]** | PASS | `PostMedia`, `CommunityPost.fromJson` & `mediaPayload` |
| **Thumbnail** | PASS | `VideoCompress.getFileThumbnail` + `StorageRepository.uploadCommunityPostMedia` |
| **Création RPC** | PASS | `CommunityRepository.createCommunityPost` (`create_community_post` avec 15 params) |
| **Suppression UUID** | PASS | `CommunityRepository.deleteCommunityPost` (`delete-community-post` Edge Function) |

## D. Point critique — Reprise TUS
> **Après fermeture complète et redémarrage de l'application, est-il réellement possible de reprendre le même upload Bunny sans créer un nouveau `video_id` ?**
- **Réponse obligatoire** : `PARTIELLEMENT`
- **Explication** : `BunnyVideoService.uploadVideoTus` exécute l'upload TUS de manière synchrone/asynchrone en mémoire (`http.Request` avec des boucles de chunks). Si l'application est tuée ou redémarrée pendant le transfert, la variable `session` et le pointeur `Location` de TUS sont perdus. Au prochain lancement, une nouvelle session `bunny-video-upload` sera demandée, générant un nouveau `videoId`. (La reprise TUS fonctionne uniquement en cas d'interruption réseau temporaire *tant que* l'instance du service en mémoire est maintenue).

## E. Divergences avec le rapport fourni
- Le rapport d'implémentation précédent affirmait une "persistance/reprise des uploads" complète après redémarrage de l'application, alors que le code actuel ne persiste pas l'état TUS (`Upload-Offset` et `Location` URL) dans SQLite/Hive.

## F. Bugs / risques
- **Vidéos orphelines sur Bunny** : En cas de coupure de l'application pendant l'upload TUS, la ressource Bunny créée initialement par l'Edge Function reste orpheline puisque le `video_id` n'est pas persisté dans une table d'outbox locale pour reprise.
- **Appel direct `print` / `debugPrint`** : Présence de nombreux `debugPrint` de diagnostic (ce qui est acceptable pour les logs demandés, mais à nettoyer pour la production).

## G. Fichiers concernés
1. `lib/modules/module_communautes/centre/services/bunny_video_service.dart` — Service d'intégration Bunny Stream et TUS.
2. `lib/modules/module_communautes/centre/services/community_service.dart` — Service principal de création de post, compression et upload.
3. `lib/modules/module_communautes/externe/repositories/community_repository.dart` — Repository Supabase (RPC create et Edge Function delete).
4. `lib/modules/module_communautes/centre/models/community_post.dart` — Modèle de données `PostMedia` (support `videoId`, `thumbnailUrl`, etc.).
5. `lib/modules/module_communautes/interne/widgets/shared/post_media_slider.dart` — Lecteur vidéo thumbnail-first et gestion de visibilité.
6. `lib/modules/module_communautes/interne/widgets/community/feed_post_card.dart` — UI de la carte de post et menu de suppression.
7. `lib/modules/module_communautes/interne/controllers/community/community_feed_controller.dart` — Contrôleur de feed gérant la suppression avec réactivité.

## H. Tests

| Test | Statut | Observation |
| :--- | :--- | :--- |
| Texte seul | PASS | Validé par tests et exécution |
| Photo seule | PASS | Validé |
| Vidéo seule | PASS | Validé (compression + thumbnail + TUS Bunny) |
| Plusieurs médias | PASS | Validé |
| Mélange photo/vidéo | PASS | Validé |
| Ordre des médias (`media[]`) | PASS | Ordre strictement préservé de bout en bout |
| Compression locale | PASS | Effectuée sur l'appareil avant upload |
| Vidéo > 50 Mo | PASS | Rejetée par validation frontend |
| Vidéo > 120 secondes | PASS | Rejetée par validation frontend |
| Upload TUS Bunny | PASS | Fonctionnel en session active |
| Interruption réseau temporaire | PASS | Reprise possible via le client HTTP si la session est active |
| Fermeture application pendant upload | FAIL | Perte de la session en mémoire, création d'un nouveau `videoId` au retry |
| Suppression post (Edge Function) | PASS | `delete-community-post` opérationnel avec nettoyage Storage/DB |
| Double-clic suppression | PASS | Protégé par `_deletingPostIds` |

## I. Recommandations (Aucun code modifié)
1. **Persistance locale TUS** : Pour atteindre une resumabilité à 100% après redémarrage de l'application, stocker dans la table SQLite locale (`CommunityLocalDao`) l'état d'upload en cours (`postId`, `videoId`, `filePath`, `tusEndpoint`, `uploadedBytes`, `totalBytes`).
2. **Nettoyage des logs** : Remplacer ou encapsuler les `debugPrint('[VIDEO_TEST] ...')` par un système de logging unifié avant la mise en production finale.
