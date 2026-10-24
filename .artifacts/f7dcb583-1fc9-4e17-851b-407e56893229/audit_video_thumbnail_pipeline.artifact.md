# Rapport d'Audit — Pipeline de Génération et Upload des Thumbnails Vidéo

## A. Fichier responsable de la sélection vidéo
- `lib/modules/module_communautes/interne/pages/community/create_community_post_screen.dart` (sélection via `MediaGallerySheet`)

## B. Fichier responsable de la génération thumbnail
- Aucun fichier existant ne génère actuellement de miniature pour les vidéos postées dans les communautés.

## C. Génération thumbnail
- **N'existe pas** (la génération par `VideoCompress.getFileThumbnail` n'est utilisée que pour la prévisualisation locale dans l'éditeur de post, mais pas pour l'upload persistant).

## D. Bucket thumbnail
- Non défini (devrait être stocké dans le bucket `community-videos` ou `community-media`).

## E. Path thumbnail
- Non défini (devrait suivre la structure des médias communautaires).

## F. Upload thumbnail
- **Absent** (aucun appel d'upload n'est effectué pour la miniature vidéo).

## G. Construction PostMedia
- `lib/modules/module_communautes/centre/services/community_service.dart` (méthode `createCommunityPost`)
- Ligne approximative : ~565
```dart
mediaPayload.add({
  'type': 'video',
  'url': videoUrl,
  'thumbnail_url': null, // <-- Hardcodé à null
  'duration_ms': null,   // <-- Hardcodé à null
  'size_bytes': await videoFile.length(),
});
```

## H. Valeur envoyée à `create_community_post`
```json
{
  "type": "video",
  "url": "https://.../video.mp4",
  "thumbnail_url": null,
  "duration_ms": null,
  "size_bytes": 4500000
}
```

## I. Cause exacte du `thumbnail_url: null`
La cause est univoque et située dans le service `CommunityService.createCommunityPost` (`lib/modules/module_communautes/centre/services/community_service.dart`). Lors de l'itération sur les fichiers vidéo sélectionnés :
1. Le code compresse la vidéo via `VideoCompress.compressVideo`.
2. Il upload la vidéo brute/compressée vers Supabase Storage via `_storage.uploadCommunityPostVideo`.
3. Il ajoute l'objet vidéo au payload `mediaPayload` en affectant explicitement `'thumbnail_url': null` et `'duration_ms': null`.
Aucune extraction de frame (via `VideoCompress.getFileThumbnail` par exemple) n'est réalisée pour générer un fichier d'image miniature, et aucun upload de cette miniature vers le Storage n'est effectué. Par conséquent, le backend reçoit et persiste `thumbnail_url: null`.

## J. Correction minimale proposée (Pour information)
1. Lors de l'upload d'une vidéo dans `CommunityService.createCommunityPost`, générer le fichier de miniature locale via `VideoCompress.getFileThumbnail(file.path, quality: 50)`.
2. Uploader ce fichier miniature vers Supabase Storage (bucket `community-videos` ou `community-media`) via `_storage.uploadCommunityPostMedia` pour obtenir son URL publique.
3. Renseigner `'thumbnail_url': thumbnailUrl` et éventuellement `'duration_ms'` dans l'objet média ajouté à `mediaPayload`.
*(Conformément aux instructions, aucun code n'a été modifié lors de cette étape d'audit).*
