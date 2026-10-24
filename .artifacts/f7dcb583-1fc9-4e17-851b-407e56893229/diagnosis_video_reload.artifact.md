# Rapport de Diagnostic — Rechargement des vidéos au scroll dans le feed communautaire

## A. Diagnostic
> La vidéo se recharge parce que le `VideoPlayerController` est instancié directement dans l'état local (`initState`) du widget `_VideoTile` et détruit (`dispose`) dès que le widget sort du viewport et est démonté par la liste (`ListView`), ce qui force une ré-initialisation asynchrone complète (téléchargement/initialisation du flux) à chaque retour dans le viewport.

## B. Cause racine
- **Fichier** : `lib/modules/module_communautes/interne/widgets/shared/post_media_slider.dart`
- **Classe** : `_VideoTile` et `_VideoTileState`
- **Méthode** : `initState()` et `dispose()`
- **Ligne approximative** : ~145-200

## C. Cycle actuel
1. **Premier affichage** : Le post entre dans le viewport → `FeedPostCard` est créé → `PostMediaSlider` est rendu → `_VideoTile` est instancié → `initState()` appelle `_initializeVideo()` → Un nouveau `VideoPlayerController` est créé et initialisé de manière asynchrone → La vidéo s'affiche.
2. **Scroll hors viewport** : L'utilisateur scrolle vers le bas → Le post sort de l'écran et est démonté par le garbage collector / recyclage de la liste → `_VideoTileState.dispose()` est appelé → `_controller?.dispose()` détruit définitivement le contrôleur et coupe le flux.
3. **Retour au post** : L'utilisateur remonte → Le post rentre à nouveau dans le viewport → `FeedPostCard` / `_VideoTile` sont recréés à neuf → Un tout nouveau `VideoPlayerController` est créé et ré-initialisé depuis le début, provoquant l'effet visuel de rechargement.

## D. Preuves (Traçage attendu)
```text
[POST_VIDEO] postId=community_post_123
[POST_CARD] created postId=community_post_123
[VIDEO_TILE] initState url=https://.../video1.mp4
[VIDEO_CONTROLLER] created url=https://.../video1.mp4
[VIDEO_CONTROLLER] initialize start
[VIDEO_CONTROLLER] initialize completed
...
[POST_CARD] disposed postId=community_post_123
[VIDEO_TILE] dispose url=https://.../video1.mp4
[VIDEO_CONTROLLER] disposed
...
[POST_CARD] created postId=community_post_123
[VIDEO_TILE] initState url=https://.../video1.mp4
[VIDEO_CONTROLLER] created url=https://.../video1.mp4
[VIDEO_CONTROLLER] initialize start
[VIDEO_CONTROLLER] initialize completed
```

## E. Réseau
- **Refetch Supabase** : NON (le post est déjà présent dans la liste locale en mémoire dans le contrôleur du feed).
- **Téléchargement Storage répété** : OUI (à chaque destruction et recréation du contrôleur, le lecteur redemande le flux média distant via HTTP ou recharge le fichier).
- **Cache utilisé** : Cache HTTP standard de bas niveau (si activé par le player natif), mais pas de mise en cache ou de réutilisation du `VideoPlayerController` ou de pool de lecture.

## F. Player
- **Controller détruit hors viewport** : OUI (`dispose()` appelle `_controller?.dispose()`).
- **Controller recréé au retour** : OUI (`initState()` instancie un nouveau `VideoPlayerController`).
- **Player réutilisé** : NON.

## G. Cause secondaire éventuelle
- Absence de `AutomaticKeepAliveClientMixin` ou de gestion de visibilité (`VisibilityDetector`) pour maintenir les posts actifs en mémoire tampon.
- Absence d'un service global ou d'un gestionnaire de cache pour les instances de `VideoPlayerController`.

## H. Proposition d'architecture
Pour éviter les rechargements :
1. **Pool de contrôleurs vidéo / Cache singleton** : Conserver un cache LRU des `VideoPlayerController` récemment initialisés par URL de vidéo, ou attacher le contrôleur au modèle `PostMedia` / `CommunityPostMedia` géré par le contrôleur de feed (ou un service dédié).
2. **Gestion de visibilité (`VisibilityDetector`)** : Mettre en pause la vidéo lorsque le post sort partiellement ou totalement du viewport au lieu de détruire aveuglément le contrôleur, ou libérer la mémoire uniquement si le cache dépasse une limite (ex: max 3 players actifs simultanément).
3. **Préchargement intelligent** : Initialiser le contrôleur du média suivant/précédent en arrière-plan.

## I. Fichiers concernés (pour information, non modifiés)
- `lib/modules/module_communautes/interne/widgets/shared/post_media_slider.dart`
- `lib/modules/module_communautes/interne/controllers/community/community_feed_controller.dart`

## J. Modification de code
Conformément aux instructions, **aucun code n'a été modifié**. Ce rapport constitue le diagnostic complet requis.
