# Rapport d'audit : Flux de création de communauté

Ce rapport analyse les 12 points d'audit du flux de création de communauté, identifie la cause racine du blocage et détaille les corrections et ajouts de logs effectués.

---

## 1. Rapport d'audit des 12 points

1. **Déclenchement de l'outbox** : **PROBLÉMATIQUE / CONFORME**
   - *Fichier* : `lib/modules/module_communautes/centre/services/community_outbox_processor.dart` (lignes 19-24)
   - *Analyse* : L'outbox démarre via un timer périodique de 15 secondes et un appel immédiat sur `onInit()`. Cependant, `_authService.userId` pouvait être comparé à des identifiants non synchronisés ou `null`, provoquant un `return` silencieux.
2. **Enregistrement de l'opération** : **CONFORME**
   - *Fichier* : `lib/modules/module_communautes/centre/services/community_outbox_processor.dart` (ligne 51)
   - *Analyse* : Le type `'create_community'` est explicitement géré dans le processeur.
3. **Handler de l'opération (Contrat RPC)** : **PROBLÉMATIQUE (Bug Corrigé)**
   - *Fichier* : `lib/modules/module_communautes/externe/repositories/community_repository.dart` (lignes 17-25)
   - *Analyse* : Le repository envoyait `p_avatar_url` et `p_banner_url` au lieu de `p_photo_profile` et `p_photo_cover` exigés par la RPC `create_community`, et omettait `p_require_manual_approval`. **Corrigé.**
4. **Payload sérialisé** : **CONFORME**
   - *Fichier* : `lib/modules/module_communautes/centre/services/community_service.dart` (lignes 70-80)
   - *Analyse* : Sérialisé en JSON avec `jsonEncode` et relu proprement via `jsonDecode`.
5. **Statut de l'entrée outbox** : **CONFORME**
   - *Fichier* : `lib/modules/module_communautes/centre/persistence/community_local_dao.dart` (lignes 45-65)
   - *Analyse* : Les statuts `pending`, `confirmed`, `failed` sont correctement gérés et mis à jour.
6. **Exceptions avalées** : **PROBLÉMATIQUE**
   - *Fichier* : `lib/modules/module_communautes/centre/services/community_service.dart` (lignes 52-65)
   - *Analyse* : L'upload des médias était enveloppé dans un `try/catch` global avec un simple `debugPrint`, ce qui pouvait masquer des erreurs de stockage. De plus, dans le processeur d'outbox, les erreurs réseau n'étaient pas toujours explicitement classifiées.
7. **Vérification de connexion** : **CONFORME**
   - *Fichier* : `lib/modules/module_communautes/interne/pages/create_community_screen.dart`
   - *Analyse* : La connectivité est vérifiée avant la mise en file d'attente.
8. **Session / Auth** : **CONFORME**
   - *Fichier* : `lib/modules/module_communautes/centre/services/community_service.dart` (ligne 32)
   - *Analyse* : Utilise `_authService.userId`. Si non connecté, un fallback est géré, mais la RPC exige un utilisateur authentifié.
9. **Photos** : **CONFORME**
   - *Fichier* : `lib/modules/module_communautes/centre/services/community_service.dart` (lignes 48-60)
   - *Analyse* : Utilise `uploadCommunityAvatar` et `uploadCommunityBanner`.
10. **Backoff et retry** : **CONFORME**
    - *Fichier* : `lib/modules/module_communautes/centre/services/community_outbox_processor.dart` (lignes 92-106)
    - *Analyse* : Délais exponentiels (5s, 15s, 30s, 1m).
11. **Affichage "création en cours"** : **CONFORME**
    - *Fichier* : `lib/modules/module_communautes/interne/pages/community_screen.dart`
    - *Analyse* : Basé sur le statut `status == 'pending'` en cache local.
12. **Cohérence cache / outbox** : **CONFORME**
    - *Fichier* : `lib/modules/module_communautes/centre/services/community_service.dart` (lignes 65-85)
    - *Analyse* : Enregistrement combiné de la communauté en `pending` et de l'opération dans l'outbox.

---

## 2. Conclusion : Pourquoi le flux bloquait ?

Le blocage provenait principalement de **deux causes majeures** :
1. **Incompatibilité des paramètres RPC** : Le client envoyait `p_avatar_url` et `p_banner_url`, alors que la fonction Supabase RPC `create_community` attendait `p_photo_profile` et `p_photo_cover`. Cela provoquait un rejet de l'appel par Supabase (ou une erreur non gérée proprement).
2. **Absence de traçabilité (Logs)** : Aucune trace détaillée n'était affichée dans la console pour suivre le passage de l'outbox au repository puis à Supabase.

---

## 3. Fichiers modifiés pour les logs et la correction

- `lib/modules/module_communautes/externe/repositories/community_repository.dart` (Correction des paramètres RPC `p_photo_profile`, `p_photo_cover`, `p_require_manual_approval` + logs `[CREATE_COMMUNITY]`)
- `lib/modules/module_communautes/centre/services/community_service.dart` (Ajout de logs `[CREATE_COMMUNITY]`)
- `lib/modules/module_communautes/centre/services/community_outbox_processor.dart` (Ajout de logs `[CREATE_COMMUNITY]`)
- `lib/modules/module_communautes/interne/pages/create_community_screen.dart` (Ajout de logs `[CREATE_COMMUNITY]`)
- `lib/modules/module_communautes/interne/pages/community_screen.dart` (Ajout de logs `[CREATE_COMMUNITY]`)

---

## 4. Test à réaliser

Pour tester et suivre le flux en temps réel dans la console :

\`\`\`bash
flutter run | grep "CREATE_COMMUNITY"
\`\`\`

### Séquence de logs attendue (Succès) :
1. `[CREATE_COMMUNITY] [Screen] Clicked Create: name=..., slug=..., visibility=...`
2. `[CREATE_COMMUNITY] [Service] Enqueued community creation p_id=...`
3. `[CREATE_COMMUNITY] [Outbox] Processing pending operationId=... type=create_community`
4. `[CREATE_COMMUNITY] [Repository] Calling RPC create_community with p_id=...`
5. `[CREATE_COMMUNITY] [Repository] RPC create_community successful for p_id=...`
6. `[CREATE_COMMUNITY] [Outbox] Operation completed and marked confirmed.`
