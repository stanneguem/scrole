# Rapport d'Audit Ciblé & Factuel — Frontend Media Pipeline

## 1. Vérification de la construction de `mediaPayload`
- **Mécanisme actuel** : Dans `CommunityService.createCommunityPost`, les fichiers sont parcourus séquentiellement via une boucle `for (final file in imageFiles)` avec des `await` successifs.
- **Séquentiel / Future.wait** : Exécution strictement séquentielle (itérative), ce qui garantit que l'ordre des éléments dans `mediaPayload` correspond exactement à l'ordre d'origine de `imageFiles`.
- **Scénario `Photo A → Vidéo A → Photo B → Vidéo B → Photo C`** : L'ordre est parfaitement préservé car chaque média est traité et ajouté à `mediaPayload` dans l'ordre précis de la liste d'entrée. Aucun réarrangement asynchrone n'intervient.

## 2. Vérification de la détection photo / vidéo
- **Code actuel** : `final isVideo = pathLower.endsWith('.mp4') || pathLower.endsWith('.mov') || pathLower.endsWith('.avi') || pathLower.endsWith('.webm') || pathLower.endsWith('.mkv') || pathLower.endsWith('.3gp') || pathLower.endsWith('.m4v');`
- **Source** : Uniquement l'extension du chemin du fichier (`pathLower`). Le type MIME n'est pas vérifié.
- **Risque réel** : Si un fichier image (photo) possède par erreur une extension reconnue ou si un fichier temporaire est mal nommé, il sera traité comme une vidéo.

## 3. Vérification de `PostMedia.fromJson`
- **Code réel** :
  ```dart
  factory PostMedia.fromJson(Map<String, dynamic> json) {
    final type = (json['type'] ?? 'photo').toString().toLowerCase();
    final url = (json['url'] ?? json['media_url'] ?? '').toString();
    final videoId = json['video_id']?.toString();
    final isVideo = type == 'video' || (videoId != null && videoId.isNotEmpty) || url.toLowerCase().endsWith('.mp4') || url.toLowerCase().endsWith('.mov') || url.toLowerCase().endsWith('.avi') || url.toLowerCase().endsWith('.m3u8');
    ...
  }
  ```
- **Problème identifié** : L'évaluation de `isVideo` utilise un `||` large incluant `(videoId != null && videoId.isNotEmpty)` ou des extensions d'URL. Si une photo possède par inadvertance un `videoId` résiduel ou non nul dans les données JSON, elle sera considérée à tort comme une vidéo lors de la lecture du feed.

## 4. Vérification du contrat de `p_media`
- `CommunityService` envoie un tableau unique `mediaPayload` ordonné à `p_media`.
- Les structures pour `photo` et `video` correspondent exactement aux spécifications Bunny / Supabase.

## 5. Conclusion sur la cause du problème (Options A à E)
- **Option C** : Le bug de confusion photo/vidéo lors de l'affichage ou du traitement provient en grande partie de la logique de fallback heuristique dans `PostMedia.fromJson` (`isVideo = type == 'video' || (videoId != null && videoId.isNotEmpty) || ...`) qui ne se base pas strictement sur `type == 'video'`.

## 6. Synthèse et Recommandations
- **Cause racine confirmée** : `PostMedia.fromJson` utilise des conditions heuristiques larges (`videoId != null`, extensions d'URL) au lieu de se fier uniquement et strictement à `type == 'video'`.
- **Risques secondaires** : Détection basée uniquement sur l'extension du fichier lors de l'upload.
- **Fichiers exacts à modifier** :
  1. `lib/modules/module_communautes/centre/models/community_post.dart`
  2. `lib/modules/module_communautes/centre/services/community_service.dart`
- **Correction minimale recommandée** : Rendre la détermination du type de média stricte et basée uniquement sur `type == 'video'` (ou `type == 'photo'`), sans inférence d'URL ou de présence de `videoId`.
- **Tests à effectuer** : Création d'un post 100% photos, puis un post 100% vidéos, puis un post mixte, et vérification du rendu dans le feed.
