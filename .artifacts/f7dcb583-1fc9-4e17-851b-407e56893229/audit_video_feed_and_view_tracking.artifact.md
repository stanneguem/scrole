# Audit Frontend & Conception — Vidéos des posts, Thumbnail, Auto-Pause et Tracking des vues

## 1. Audit de l'architecture actuelle

### 1.1 Création et cycle de vie des `VideoPlayerController`
- **Où sont-ils créés ?** Dans la méthode `initState()` du widget d'état `_VideoTileState` (`lib/modules/module_communautes/interne/widgets/shared/post_media_slider.dart`).
- **Où sont-ils initialisés ?** Dans `_initializeVideo()`, appelé asynchroniquement depuis `initState()`.
- **Où sont-ils lancés ?** Actuellement, le lecteur démarre manuellement au tap de l'utilisateur sur l'overlay "Play", mais la ressource réseau est immédiatement téléchargée et initialisée dès que le widget entre dans le viewport.
- **Où sont-ils mis en pause ?** Sur un nouveau tap de l'utilisateur ou lors du démontage.
- **Où sont-ils détruits (`dispose()`) ?** Dans la méthode `dispose()` de `_VideoTileState`, appelée dès que le post sort du viewport et que le widget est démonté par la liste (`ListView.builder`).
- **Déclencheur de création** : Le simple fait qu'un post contenant une vidéo apparaisse dans le viewport déclenche le montage du widget et l'initialisation du contrôleur vidéo.

### 1.2 Gestion des thumbnails et du cache image
- `thumbnail_url` est correctement parsé dans le modèle `PostMedia` (`CommunityPost.fromJson`).
- Actuellement, le widget `_VideoTile` initialise directement le lecteur vidéo sans afficher de manière exclusive une image `thumbnail_url` en tant qu'état initial (il affiche un écran noir avec un indicateur de chargement circulaire en attendant l'initialisation du player).
- Le projet utilise `CachedNetworkImage` / `AppCachedImage` pour les images fixes, ce qui est idéal pour afficher la miniature sans consommer les ressources d'un lecteur vidéo.

### 1.3 Visibilité et absence de gestionnaire global
- Il n'y a actuellement aucun gestionnaire global (`VideoManager`) ni de `VisibilityDetector` dans le module communautés.
- Les contrôleurs sont instanciés de manière isolée par chaque `_VideoTile` et détruits immédiatement hors écran.

---

## 2. Conception de l'Architecture "Thumbnail-First"

### 2.1 État initial (Thumbnail seule)
1. Lorsqu'un post vidéo apparaît dans le feed, **aucun** `VideoPlayerController` n'est créé.
2. Le composant affiche la `thumbnail_url` (ou le premier frame / image statique) via `AppCachedImage` avec une icône "Play" centrée.
3. Consommation mémoire et réseau quasi nulle au scroll initial.

### 2.2 Action utilisateur (Tap sur la Thumbnail)
1. L'utilisateur appuie sur la miniature vidéo.
2. Un indicateur de chargement s'affiche par-dessus la miniature.
3. Le `VideoManager` (singleton ou contrôleur global) crée ou récupère un `VideoPlayerController` pour cette URL.
4. Dès que le player est initialisé, la miniature est masquée et la vidéo démarre immédiatement.

### 2.3 Intégration dans le Carrousel (Mixed Media)
- Dans un carrousel contenant `[ PHOTO ] [ VIDEO ] [ PHOTO ]` :
  - Les photos s'affichent normalement via `AppCachedImage`.
  - La vidéo s'affiche sous forme de miniature interactive.
  - Le changement de page (swipe) ne crée pas de lecteur vidéo tant que l'utilisateur n'a pas explicitement cliqué sur la lecture de la vidéo.

---

## 3. Stratégie Auto-Pause et Gestion des Contrôleurs (`VideoManager`)

### 3.1 Auto-Pause par visibilité (`visibleFraction`)
- Utilisation d'un détecteur de visibilité (ex: package `visibility_detector` ou calcul de viewport natif).
- **Seuil recommandé** : `visibleFraction < 0.5` (moins de 50 % visible).
  - *Pourquoi ?* Si un utilisateur scrolle et que la vidéo est coupée à plus de la moitié par le bord de l'écran, il est probable qu'il lise un autre contenu. Une valeur de 50 % évite les coupures intempestives lors de micro-scrolls de lecture.
  - **Action** : Mettre la vidéo en **pause** automatique.

### 3.2 Distinction entre Pause et Dispose (Pooling intelligent)
- **Hors écran proche (< 50 % ou partiellement masqué)** : `pause()`. Le contrôleur est conservé en mémoire pour une reprise instantanée (`resume()`) si l'utilisateur remonte immédiatement.
- **Hors écran lointain / Disparition complète du viewport (0 % ou défilement rapide de 5+ posts)** : Le `VideoManager` libère le contrôleur (`dispose()`) pour économiser la RAM, en remplaçant le lecteur par la thumbnail statique.
- **Limite de contrôleurs actifs** : Maximum **2 à 3 `VideoPlayerController` actifs** simultanément dans toute l'application. Au-delà, le plus ancien non visible est proprement libéré (`dispose()`).

---

## 4. Conception du Tracking des Vues (`Video Views`)

### 4.1 Définition rigoureuse d'une vue ("True View")
Pour éviter les fausses vues (scrolls rapides, apparitions de 200 ms), une vue de publication vidéo doit répondre à des critères stricts :
- **Option retenue (Recommandée pour Scrole)** : **Option B combinée** — La vidéo doit être **visible à au moins 50 %** ET lue en continu pendant **au moins 3 secondes** (ou visionnée à plus de 50 % de sa durée si la vidéo fait moins de 3 secondes).

### 4.2 Anti-doublons et Métriques (`unique_viewers` vs `total_views`)
- **Unique Viewers** : Un même utilisateur ne peut incrémenter le compteur d'audience unique (`unique_viewers`) qu'**une seule fois par post**, indépendamment du nombre de fois qu'il revient visionner la vidéo.
- **Total Views** : Incrémenté à chaque nouveau visionnage qualifié (après un certain intervalle de temps hors écran, ex: 30 minutes, ou après un retour sur le post après l'avoir complètement quitté).

### 4.3 Traitement local, Debounce et Offline-First
- **Pas de requête temps réel au moindre événement** :
  1. Le `VideoManager` / tracker de vue détecte le franchissement du seuil (50 % visible + 3s de lecture).
  2. L'événement est marqué localement (en mémoire et/ou base SQLite locale / outbox).
  3. Un mécanisme de *debounce* (ex: envoi groupé toutes les 15 secondes ou à la fermeture de l'écran / mise en arrière-plan) transmet les vues au backend.
- **Mode Offline** : Si l'utilisateur est hors ligne, les événements de vue sont stockés dans la table locale (`community_outbox` ou table dédiée aux vues de posts) et synchronisés automatiquement dès que la connexion est rétablie.

---

## 5. Matrice de Tests à Valider (Pré-implémentation)

| N° | Scénario | Comportement Attendu |
|:---|:---|:---|
| **Test 1** | Post vidéo visible mais jamais touché | Miniature affichée, 0 contrôleur créé, pas de téléchargement vidéo. |
| **Test 2** | Tap sur la thumbnail | Chargement, initialisation du contrôleur, lecture de la vidéo. |
| **Test 3** | Scroll légèrement (vidéo < 50% visible) | Pause automatique de la vidéo. |
| **Test 4** | Retour rapide sur la vidéo | Reprise instantanée (`resume()`) sans réinitialisation réseau. |
| **Test 5** | Scroll très loin (hors viewport prolongé) | Contrôleur libéré (`dispose()`), retour à l'affichage de la thumbnail. |
| **Test 6** | Retour après un scroll lointain | Affichage de la thumbnail, ré-initialisation propre au clic suivant. |
| **Test 7** | Visionnage > 3 secondes à 50% de visibilité | Vue qualifiée et enregistrée. |
| **Test 8** | Scroll très rapide (passage éclair) | Aucune fausse vue enregistrée. |
| **Test 9** | Même utilisateur regarde 2 fois | `total_views` incrémenté 2 fois, `unique_viewers` incrémenté 1 seule fois. |

---

## 6. Analyse des Risques et Performances
- **Fuites mémoire** : Évitées par la limite stricte du nombre de contrôleurs actifs gérée par le `VideoManager`.
- **Consommation CPU / GPU** : Réduite drastiquement car les vidéos inactives ne consomment aucune ressource de décodage matériel.
- **Fluidité du Scroll** : Inchangée ou améliorée (plus de saccades dues à la création simultanée de dizaines de contrôleurs vidéo au défilement).

---

## 7. Back-end à Prévoir (Pour information future)
- Table ou colonnes pour stocker les vues : `community_post_views` (`post_id`, `user_id`, `viewed_at`, `duration_watched_ms`).
- RPC ou endpoint d'incrémentation des vues avec déduplication par utilisateur.
