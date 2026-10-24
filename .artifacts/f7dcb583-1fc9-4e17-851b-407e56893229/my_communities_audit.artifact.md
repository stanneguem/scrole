# AUDIT FRONTEND — Mes communautés

## 1. Écran concerné
- **Fichier** : `lib/modules/module_communautes/interne/pages/community/community_list_screen.dart`
- **Widget** : `CommunityListScreen`
- **Controller** : `CommunityListController` (`lib/modules/module_communautes/interne/controllers/community/community_list_controller.dart`)
- **Route** : `/community_list` / Routes des communautés

## 2. Flux actuel
```text
CommunityListScreen
 ↓
CommunityListController.onInit()
 ↓
_listenToLocalCommunities() (écoute SQLite via stream _localDao.changes)
 +
refreshData() (Appelle _service.refreshJoinedCommunities(userId) avec timeout de 10s)
 ↓
CommunityRepository.getMyCommunities()
 ↓
Supabase RPC / Tables (communities, community_members)
```

## 3. Cache
- **Système utilisé** : SQLite (`AppDatabase` / `CommunityLocalDao`)
- **Modèle** : `CommunityModel`, `CommunityWithRole`
- **Stockage** : Tables `communities` et `community_members`
- **Clé / Isolation** : `user_id` dans `community_members` (`WHERE m.user_id = ?`)
- **Données sauvegardées** : `id`, `name`, `slug`, `description`, `avatar_url`, `banner_url`, `visibility`, `status`, `member_count`, `role_id`
- **Lecture / Écriture** : `_service.watchJoinedCommunities(userId)` (Stream SQLite) / `refreshJoinedCommunities` (Transaction SQLite)

## 4. Chargement actuel
À l'ouverture de l'écran, `CommunityListController.onInit()` initialise l'écouteur local (`_listenToLocalCommunities`) et déclenche en parallèle `refreshData()`. `status` est initialement mis à `CommunityStatus.loading`.

## 5. Risques identifiés

### CRITIQUE
- **Timeout bloquant et basculement en erreur** : Dans `CommunityListController.refreshData()`, si le chargement réseau (ou la requête RPC) dépasse le `timeout(const Duration(seconds: 10))` ou échoue, et que `joinedCommunities` est vide au moment de l'erreur, le code bascule dans le bloc `catch` et définit `status.value = CommunityStatus.error` (`CommunityError`), masquant totalement le cache SQLite existant.

### ÉLEVÉ
- **Race condition entre Stream local et Refresh réseau** : `refreshData()` et `_listenToLocalCommunities()` sont lancés simultanément à l'initialisation. Si le réseau est très lent ou en échec, le premier état du stream local peut arriver après ou avant le timeout, entraînant un affichage intermittent d'erreurs ou d'écrans vides.

### MOYEN
- **Pas de suppression des communautés quittées** : `refreshJoinedCommunities` insère ou met à jour les communautés reçues du backend via `ConflictAlgorithm.replace`, mais ne supprime pas de SQLite les communautés dont l'utilisateur ne fait plus partie.

## 6. Réseau
- **Réseau OK** : Chargement local immédiat via SQLite puis mise à jour silencieuse par le réseau.
- **Réseau lent / Timeout (>10s)** : Déclenchement d'une exception de timeout dans `refreshData`, basculant l'UI en état d'erreur si `joinedCommunities` est vide.
- **Réseau indisponible (Offline)** : Si le cache SQLite contient des données, le Stream SQLite émet les données et l'écran s'affiche. Si le cache est vide et que le réseau est absent, `refreshData` échoue et affiche l'écran d'erreur.

## 7. Cache-first
- **CACHE-FIRST : PARTIEL**
- *Pourquoi* : Bien que le DAO lise SQLite, le contrôleur attend que le flux réseau se termine ou timeout avant de finaliser le statut (`CommunityStatus.success` / `error`), et un timeout réseau peut écraser l'affichage en affichant un écran d'erreur si la liste locale n'avait pas encore émis assez vite.

## 8. Isolation utilisateur
- **CACHE ISOLÉ PAR USER : OUI**
- *Pourquoi* : Les requêtes DAO filtrent explicitement par `user_id` (`WHERE m.user_id = ?`).

## 9. Feed / membres
- **Feed** : NON (aucun post ou feed n'est chargé).
- **Membres** : NON (aucun membre n'est chargé).
- **Événements / Activités** : NON.

## 10. Cause probable du bug
> *« De temps en temps, Mes communautés ne s'affiche pas alors que l'utilisateur est membre. »*

1. **Timeout réseau de 10 secondes trop strict combiné au blocage d'erreur** : Si le backend Supabase met plus de 10 secondes à répondre ou si la connexion mobile est instable, `refreshData()` lève un `TimeoutException`. Le bloc `catch` vérifie `if (joinedCommunities.isEmpty)` : si le flux local SQLite n'a pas encore émis au moment précis de l'exception, l'écran passe en `CommunityStatus.error` au lieu d'afficher le cache ou un état de secours.
2. **Absence de chargement synchrone initial du cache** : Le contrôleur attend l'émission du stream pour définir le succès, mais le timeout global englobe l'appel réseau (`refreshJoinedCommunities`). Si le réseau bloque, le contrôleur ne considère pas le cache comme une source suffisante pour valider le succès de l'affichage.

## 11. Verdict
- CACHE : **PROBLÈME**
- CHARGEMENT : **PROBLÈME**
- SYNCHRONISATION : **PROBLÈME**
- GESTION ERREUR : **PROBLÈME**
- ISOLATION USER : **OK**
- CHARGEMENT INUTILE DU FEED : **NON**
- CHARGEMENT INUTILE DES MEMBRES : **NON**
