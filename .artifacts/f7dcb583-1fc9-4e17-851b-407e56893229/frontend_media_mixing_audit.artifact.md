# Rapport d'Audit — Analyse du traitement des médias mixtes (Photos / Vidéos) dans le Frontend Scrole

## A. Sélection des médias
- **Fichiers / classes concernés** : `MediaGallerySheet` (`lib/shared/widgets/media_gallery_sheet.dart`), `CreatePostSheet` / `CreateCommunityPostScreen`.
- **Fonctionnement actuel** : L'utilisateur sélectionne des médias (photos et/ou vidéos) via la galerie. Le composant maintient une liste ordonnée unique (`List<AssetEntity>` puis convertie en `List<XFile>`) transmise via `onSelected(List<XFile>)`.
- **Problème éventuel** : Aucune liste séparée n'est utilisée ; l'ordre initial est conservé dans le tableau brut `imageFiles`.

## B. Modèle média
- **Fichiers** : `PostMedia` (`lib/modules/module_communautes/centre/models/community_post.dart`), `MediaAsset` (`lib/shared/models/media_asset.dart`).
- **Structure** : Contient `type`, `url`, `videoId`, `thumbnailUrl`, `durationMs`, `sizeBytes`, `isVideo`.
- **Problème éventuel** : Dans `PostMedia.fromJson`, le test `isVideo` se basait parfois sur l'absence de type explicite ou une inspection d'URL partielle. Cependant, le modèle distingue proprement `photo` et `video`.

## C. Upload photo
- **Fichiers / classes** : `CommunityService` (`lib/modules/module_communautes/centre/services/community_service.dart`), `StorageRepository`.
- **Pipeline** : Compression locale de l'image → upload vers Supabase Storage (`community-media`) → récupération de l'URL publique.
- **Résultat produit** : `{'type': 'photo', 'storage': 'supabase', 'url': '...'}`.

## D. Upload vidéo
- **Fichiers / classes** : `CommunityService`, `BunnyVideoService`.
- **Pipeline** : Compression locale au format MP4/H.264 → `prepare` Bunny (action Edge Function) → Upload TUS Bunny (`https://video.bunnycdn.com/tusupload`) → Polling statut (`ready`) → URLs Bunny HLS (`playlist.m3u8` & `thumbnail.jpg`).
- **Résultat produit** : `{'type': 'video', 'storage': 'bunny', 'client_media_id': '...', 'video_id': '...', 'url': '...', 'thumbnail_url': '...', 'duration_ms': ..., 'size_bytes': ...}`.

## E. Construction de p_media
- **Fichiers / méthode** : `CommunityService.createCommunityPost` (`lib/modules/module_communautes/centre/services/community_service.dart`).
- **Code logique actuel** : Itération sur `imageFiles` avec vérification de l'extension (`.mp4`, `.mov`, `.avi`, `.webm`, `.mkv`, `.3gp`, `.m4v`).
- **Problème identifié** : La détection `isVideo` reposait uniquement sur les extensions de fin de nom de fichier (`pathLower.endsWith(...)`). Si une photo sélectionnée ou un fichier temporaire issu d'un picker avait une extension non standard ou si la condition était évaluée de manière trop large, une photo pouvait être prise pour une vidéo (ou inversement). De plus, l'ordre des éléments dans `mediaPayload` est indexé sur l'itération synchrone/asynchrone, mais l'upload TUS étant asynchrone et pouvant prendre du temps, il est crucial de s'assurer que l'insertion dans `mediaPayload` respecte l'indice d'origine (`imageFiles`) plutôt que l'ordre de fin d'upload.

## F. Appel create_community_post
- **Méthode** : `CommunityRepository.createCommunityPost` / RPC `create_community_post`.
- **Paramètres envoyés** : `p_id`, `p_community_id`, `p_content`, `p_media` (liste ordonnée).
- **Problème éventuel** : Si un média photo échoue ou est mal typé dans `mediaPayload`, le RPC rejette le payload global.

## G. Récupération du feed
- **Méthode** : `PostMedia.fromJson` (`community_post.dart`).
- **Mapping `media`** : Analyse chaque objet du tableau JSONB `media` et détermine le type (`photo` ou `video`) selon la clé explicite `type` (ou `storage`).

## H. Cause racine
- Le mélange des logiques photo/vidéo provient d'une **détection fragile du type de média** basée uniquement sur les extensions de nom de fichier (`pathLower.endsWith(...)`), et du risque potentiel que des fichiers photo sans extension claire ou avec des extensions inhabituelles soient mal routés, ou que l'ordre d'insertion dans `mediaPayload` ne suive pas l'index exact de la liste d'origine `imageFiles` en cas de traitements asynchrones.

## I. Correction proposée (Audit uniquement - Non appliquée)
1. Utiliser le type MIME ou l'objet d'origine (`XFile.mimeType` ou vérification robuste) plutôt que de se fier uniquement à l'extension du chemin.
2. Garantir que `mediaPayload` est construit en préservant strictement l'index initial de `imageFiles` (par exemple en initialisant un tableau de taille fixe ou en insérant via un `Future.wait` indexé).

## J. Test de validation
Scénario : `Photo A → Vidéo A → Photo B → Vidéo B → Photo C`
Vérification que `p_media` contient exactement 5 éléments dans cet ordre strict, avec les bons `storage` (`supabase` vs `bunny`).
