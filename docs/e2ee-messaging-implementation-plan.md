# Scrole — plan d'implémentation du chiffrement de bout en bout (E2EE)

**Périmètre :** application Flutter utilisateurs + Supabase (Postgres, Realtime, Edge Functions, R2).  
**Branche étudiée :** `feature/story-video-post-reshare`  
**État :** audit réalisé ; registre public des appareils MLS déployé ; droits de consommation des KeyPackages durcis. Aucun message n'est encore chiffré et aucune activation E2EE n'est autorisée.

## 1. Décision de sécurité

Objectif : le serveur ne doit jamais recevoir le texte lisible, les clés de contenu, ni les octets lisibles des pièces jointes. Le chiffrement et le déchiffrement se font sur les appareils Flutter.

Le chiffrement TLS de Supabase reste nécessaire, mais il ne remplace pas le chiffrement de bout en bout.

La cible retenue est **Messaging Layer Security (MLS, RFC 9420)** pour les conversations privées à deux comme pour les salons communautaires. MLS est conçu pour des groupes de deux à des milliers de membres, avec confidentialité persistante et sécurité post-compromission. L'implémentation de référence retenue est **OpenMLS (Rust)**, sous licence MIT. La suite initiale recommandée est X25519 / AES-128-GCM / SHA-256 / Ed25519 ; les suites post-quantiques expérimentales ne seront pas activées en production.

Le crate OpenMLS officiel est publié en version 0.9.2 (22 octobre 2026). Les cibles Android AArch64 et iOS AArch64 sont indiquées comme « unsupported, but built on CI » : elles compilent dans la CI upstream mais ne sont pas testées par le projet. Pour la liaison Flutter/Rust, `flutter_rust_bridge` 2.13.0 est une version stable récente compatible avec Dart 3.9+ ; Scrole utilise Dart 3.12.2. La voie retenue est une intégration Rust contrôlée par Scrole, avec versions épinglées et CI dédiée. Le wrapper openmls publié sur pub.dev (2.0.1) expose déjà une API MLS et un stockage SQLCipher, mais son éditeur est toujours non vérifié et le paquet a une publication très récente ; il n'est donc pas retenu comme dépendance de production sans vérification de l'éditeur, audit de chaîne d'approvisionnement et revue de son code. Sa documentation décrit toutefois des correctifs de sécurité importants dans ses versions récentes.

**Réserve de sécurité :** OpenMLS est une implémentation de RFC 9420 maintenue par Phoenix R&D et Cryspen. Les sources consultées ne suffisent pas à affirmer qu'OpenMLS 0.9.2 a passé un audit cryptographique indépendant. Une revue indépendante est requise avant l'activation générale. Les cibles mobiles ne sont pas testées upstream.

### Modèle MLS

- Un groupe MLS par conversation directe et par salon communautaire.
- Chaque appareil d'un utilisateur est une identité MLS distincte.
- Clés privées et état MLS uniquement sur l'appareil, dans un stockage chiffré dont la clé est protégée par Keychain / Android Keystore.
- KeyPackages publics publiés sur Supabase ; leurs clés privées restent sur l'appareil.
- Messages MLS Application et événements Commit/Welcome transmis comme enveloppes opaques.
- Ajout/retrait des membres par Commit MLS ; les appareils retirés ne reçoivent pas les secrets des époques suivantes.
- Vérification d'identité par empreinte et avertissement explicite lors d'un changement de clé.
- Pas de retour silencieux au texte en clair une fois une conversation activée.

Ne pas implémenter un protocole cryptographique maison ni mélanger des clés X25519 et AES sans mécanisme MLS.

## 2. Architecture actuelle observée

### Messages directs (deux utilisateurs)

Flutter :
- `module_discussion_direct/centre/models/message.dart` expose `content`, `mediaUrls` et `audioUrl` en clair.
- `SupabaseMessagingService.insertMessage()` appelle `insert_direct_message` avec `p_text`, `p_audio_url` et `p_media_urls`.
- `MessagingRepository.sendMessage()` met en cache le message local puis l'envoie ; `sendMediaMessage()` téléverse les fichiers avant l'envoi.
- `MessagesDao` persiste actuellement le texte et les URL lisibles dans SQLite (`direct_chat_messages`).

Supabase :
- `public.direct_messages.text`, `audio_url` et `media_urls` contiennent le contenu ou les références de médias.
- RPC concernées : `insert_direct_message`, `send_direct_message`, `get_direct_messages`, `get_direct_messages_after`, `edit_direct_message`, `get_my_direct_conversations`.
- `get_my_direct_conversations` retourne `last_message_text` à la liste des conversations.
- Le trigger `notify_direct_message_push` construit actuellement le corps de notification à partir de `new.text` pour les messages texte. C'est une fuite de contenu à corriger.
- Les accusés de réception, curseurs de lecture, suppressions et dates peuvent rester des métadonnées non chiffrées.

### Salons de discussion des communautés (plusieurs membres)

Flutter :
- La conversation est implémentée dans `module_communautes/interne/pages/community_chat_groups_screen.dart`, classe `CommunityChatGroupConversation`.
- Les messages sont envoyés via `send_salon_message` ; les synchronisations initiale, incrémentale et Realtime utilisent `get_salon_messages`, `get_salon_messages_since` et `get_salon_message_delta`.
- `SalonChatLocalCache` enregistre le JSON complet des messages dans SQLite (`salon_messages.payload`).
- Texte, audio, images et vidéos suivent des chemins d'envoi différents dans le même écran.

Supabase :
- `public.community_salon_messages.content`, `audio_url`, `media_object_key` et `media_object_keys` stockent le texte ou les références de fichiers.
- RPC concernées : `send_salon_message`, `get_salon_messages`, `get_salon_messages_since`, `get_salon_message_delta`, `get_salon_messages_around`, `edit_salon_message`, `list_community_chat_groups_with_preview`.
- `list_community_chat_groups_with_preview` retourne actuellement `latest.content` comme aperçu du dernier message.
- Le trigger de notification communautaire envoie déjà un texte générique, sans inclure le contenu du message. Il faut conserver ce comportement.
- Les règles `joined_at` limitent déjà l'historique accessible à un membre à sa date d'adhésion ; elles devront rester cohérentes avec les époques de clés.

### Médias et transport

- Les directs passent par `r2-media-upload` et stockent des références de médias.
- Les salons communautaires téléversent leurs médias via `R2MediaRepository`, catégorie `salon_message_media`.
- Le bucket Storage `chat-media` est public dans le projet inspecté : il ne doit pas être utilisé pour les nouveaux médias E2EE.
- Le bucket `group-chat-media` est privé, mais le code des salons inspecté utilise actuellement le chemin R2. L'accès aux octets chiffrés devra rester authentifié et limité aux membres.
- Les notifications, aperçus de conversations, réponses citées, journaux, caches et noms de fichiers doivent être audités : chiffrer seulement la colonne texte ne suffit pas.

## 3. Modèle de clés proposé

### Identité par appareil

Créer un identifiant stable par installation Flutter et un registre serveur de clés publiques :
- `e2ee_devices` : utilisateur, appareil, version du protocole, clé publique d'identité, statut/révocation, dates ;
- `e2ee_key_packages` : KeyPackages MLS publics, à usage unique et consommés atomiquement ;
- les clés privées de signature et secrets de stockage MLS restent exclusivement sur l'appareil.

Les clés privées et états de sessions ne quittent jamais l'appareil. Le serveur ne stocke que les clés publiques et les enveloppes chiffrées. Les clés privées sont protégées par Keychain iOS / Android Keystore via un stockage sécurisé. Les états sérialisés des ratchets sont chiffrés localement et écrits de façon durable et atomique.

### Direct

1. Chaque appareil publie un KeyPackage MLS public.
2. Les appareils établissent le groupe MLS de la conversation directe et distribuent le Welcome chiffré au second participant.
3. Les deux utilisateurs et leurs autres appareils autorisés rejoignent le même groupe MLS ; chaque appareil conserve son propre état local.
4. Le contenu applicatif est chiffré avec MLS avant envoi. Supabase ne reçoit que des enveloppes chiffrées et des métadonnées minimales.
5. Chaque appareil traite les messages et commits dans l'ordre et persiste atomiquement son état MLS chiffré.

### Salon communautaire

1. Chaque appareil membre rejoint le groupe MLS du salon à l'aide d'un KeyPackage et d'un Welcome chiffré.
2. Les messages applicatifs sont chiffrés une fois par l'appareil expéditeur et relayés comme enveloppes MLS opaques.
3. Lorsqu'un membre est ajouté, retiré ou quitte le salon, un Commit MLS avance l'époque et renouvelle les secrets du groupe. Aucun message ne doit partir avec l'état d'une époque obsolète.
5. Un nouveau membre ne reçoit pas les anciennes clés : l'historique antérieur à son adhésion reste illisible, sauf partage d'historique explicite décidé séparément.
6. Un membre retiré ne peut plus lire les messages futurs. Il reste impossible de lui faire « oublier » les anciens messages qu'il a déjà reçus.

## 4. Schéma de données cible (à transformer en migrations après validation)

- Registre des appareils et pré-clés publiques.
- Enveloppes de messages directs par appareil destinataire.
- Identifiant MLS et événements Commit/Welcome/Application chiffrés par conversation ; état MLS privé conservé uniquement sur les appareils.
- Colonnes explicites `encryption_version`, `ciphertext`/enveloppes et métadonnées de protocole.
- Les colonnes historiques en clair sont conservées uniquement pour compatibilité/migration des anciens messages ; les RPC de nouvelle version doivent refuser tout message en clair après activation E2EE.
- Les RPC de lecture et d'écriture gardent les contrôles d'appartenance existants ; le serveur valide les membres et les appareils, mais ne déchiffre jamais.

Les tables de clés privées, secrets de conversation et clés de fichiers ne doivent jamais être créées côté serveur.

## 5. Médias, notifications et caches

- Chiffrer le fichier sur l'appareil avant le téléversement. Utiliser une clé aléatoire par fichier, un format AEAD/streaming authentifié et un nom d'objet opaque. La clé et le nonce sont inclus dans le payload chiffré du message, jamais dans R2.
- Ne pas charger le fichier complet en mémoire pour les vidéos volumineuses ; utiliser un chiffrement par blocs authentifiés et vérifier chaque bloc à la lecture.
- Les messages directs et communautaires ne doivent plus inclure de texte dans les push. Notification générique : « Nouveau message », avec navigation vers la conversation seulement.
- Les aperçus de liste, recherches, réponses citées et notifications sont générés après déchiffrement sur le téléphone. Le serveur ne renvoie plus `last_message_text` ou `latest.content`.
- Stocker les messages locaux sous forme chiffrée ; ne pas laisser le texte déchiffré dans SQLite, le cache média ou les logs.
- Nettoyer les fichiers temporaires en clair après chiffrement/déchiffrement, et ne jamais mettre en cache les URL présignées avec des clés de déchiffrement.

## 6. Conséquences fonctionnelles à accepter

- Scrole, Supabase, les Edge Functions et les administrateurs React.js ne peuvent pas lire les messages ou pièces jointes E2EE.
- La modération serveur ne peut plus analyser le contenu. Un signalement de message doit permettre à l'utilisateur de joindre volontairement une preuve déchiffrée et les métadonnées nécessaires, avec consentement clair.
- La recherche plein texte côté serveur, les aperçus de message dans les notifications, et toute modération automatique du texte ne seront plus possibles.
- Un appareil perdu/réinstallé ne pourra pas retrouver les anciens messages sans transfert d'appareil ou sauvegarde de clés chiffrée par un secret connu uniquement de l'utilisateur. Aucune clé de récupération en clair ne doit être conservée par Scrole.
- Les utilisateurs doivent avoir une version compatible ; pas de retour silencieux au clair après activation. Les salons nécessitent une transition coordonnée de tous les membres actifs.

## 7. Compatibilité et migration

- Les anciens messages déjà enregistrés en clair ne peuvent pas être rendus rétroactivement secrets : le serveur et ses sauvegardes ont déjà détenu leur contenu. Ils seront marqués comme historiques non E2EE ou supprimés selon une décision produit distincte.
- Déployer en phases : infrastructure des appareils et pré-clés ; conversations directes en environnement de test ; salons avec rotation de clés ; médias ; caches/notifications ; activation progressive.
- Une conversation ne passe en mode E2EE obligatoire qu'après vérification que les appareils participants sont prêts. Une fois activée, les RPC refusent les payloads non chiffrés.
- Prévoir tests de messages hors ordre, appareils multiples, pré-clés consommées simultanément, ratchet interrompu, restauration de sauvegarde, changement de clé d'identité, membre ajouté/retiré, hors ligne, pièces jointes volumineuses, suppressions/édition et notification push.

## 8. Ordre de réalisation

1. **Choix juridique et technique du SDK cryptographique** : décision prise pour OpenMLS 0.9.2 + `flutter_rust_bridge` 2.13.0, sous réserve de validation CI Android/iOS et revue de sécurité.
2. Intégrer le moteur OpenMLS natif via `flutter_rust_bridge`, le stockage MLS chiffré et les clés de stockage liées au Keychain / Android Keystore ; tests de reprise après crash/rollback. Ne pas livrer tant que les builds Android/iOS ne sont pas verts.
3. Ajouter les tables/RPC de publication des bundles et de distribution chiffrée ; RLS stricte par utilisateur/appareil et membre du salon.
4. Adapter les modèles Flutter, le dépôt direct et la conversation de salon pour chiffrer avant toute écriture réseau et déchiffrer après lecture.
5. Remplacer les aperçus et notifications contenant du texte ; enlever les chemins serveur qui lisent le contenu.
6. Chiffrer tous les médias avant R2 et verrouiller l'accès aux objets.
7. Chiffrer les caches SQLite et ajouter l'interface de vérification d'identité, transfert/récupération d'appareil et avertissements.
8. Tests sécurité, tests d'intégration, audit des politiques/RPC/Storage/Realtime, puis activation progressive.

**Critère de réussite :** en inspectant Postgres, Realtime, Storage/R2, Edge Functions, FCM et les journaux, aucune personne autre que les appareils autorisés ne peut reconstituer un message ou un média à partir des données serveur.


## 9. État opérationnel au 8 novembre 2026

- Migration `20261108230000_e2ee_mls_device_registry.sql` : registre des appareils et KeyPackages publics déployés.
- Migration `20261108231000_harden_e2ee_key_package_claims.sql` : retrait de l'UPDATE direct sur les KeyPackages ; consommation atomique exécutée par une fonction privée `SECURITY DEFINER` avec `search_path` vide, derrière une fonction publique `SECURITY INVOKER`.
- Vérification SQL effectuée : `authenticated` ne peut plus faire `UPDATE` sur `e2ee_key_packages`, `anon` ne peut pas appeler la fonction de consommation, `authenticated` peut l'appeler, wrapper public invoker et worker privé definer.
- Les anciens messages, RPC d'envoi, notifications et caches ne sont pas modifiés. Le chiffrement E2EE n'est pas actif.
- Les Security Advisors Supabase remontent aussi des avertissements historiques globaux (fonctions SECURITY DEFINER accessibles aux rôles publics et tables RLS sans politique) ; ils ne sont pas tous liés à E2EE et doivent faire l'objet d'un audit distinct avant l'activation de la messagerie chiffrée.


## 10. Avancement de l'intégration native (8 novembre 2026)

- Crate Rust `rust/` créé avec OpenMLS 0.9.2, provider RustCrypto et Flutter Rust Bridge 2.13.0 épinglés.
- API native de capacité créée ; elle retourne explicitement `ready_for_messages = false`. Aucun chiffrement de message n'est exposé.
- Dépendances Flutter ajoutées : `flutter_rust_bridge ^2.13.0` et `flutter_secure_storage ^11.2.0`.
- Gestionnaire `lib/core/e2ee/secure_mls_storage_key.dart` ajouté : crée une clé aléatoire de 256 bits par couple utilisateur/appareil et la conserve via le stockage sécurisé de la plateforme. Le code appelant doit encore fournir un identifiant d'installation stable ; la gestion du cycle de vie et la récupération ne sont pas encore intégrées.
- Workflow GitHub Actions initial ajouté pour `cargo test` et `cargo check` sur Linux.
- Les bindings Dart générés, le `Cargo.lock`, l'initialisation native, le stockage persistant MLS et les builds Android/iOS ne sont pas encore validés. L'environnement GitHub distant utilisé pour les modifications ne permet pas d'exécuter Flutter/Cargo.
- Aucune messagerie ne consomme encore ce moteur ; les RPC, notifications et caches existants continuent de fonctionner comme avant. Ne pas activer E2EE sur des conversations réelles.


## 11. Identité d'installation et préparation locale (8 novembre 2026)

- `E2eeDeviceIdentity` ajoute un UUIDv4 aléatoire, distinct par compte Scrole sur une installation et stocké dans le coffre de la plateforme.
- Les appels concurrents via la même instance sont sérialisés par compte ; le service doit être enregistré comme singleton applicatif. Les identifiants ne sont pas des empreintes matérielles.
- `E2eeLocalKeyManager` coordonne l'identité et la clé locale de chiffrement de la future base MLS ; il n'est pas encore branché au démarrage.
- Tests unitaires ajoutés pour l'identité persistée, sa création, le rejet d'une valeur corrompue et la lecture sans création.
- Les tests ne sont pas exécutés dans l'environnement d'édition GitHub. Ils doivent être lancés localement avec `flutter test test/core/e2ee/e2ee_device_identity_test.dart`.
- Le wrapper Dart `openmls` 3.3.0 a été examiné. Il apporte un moteur complet, SQLCipher et des correctifs OpenMLS récents, mais sa propre documentation reconnaît que la clé de base de données passe par le tas Dart et ne peut pas être effacée de façon garantie. L'éditeur pub.dev n'est pas vérifié. Il n'est donc pas ajouté comme dépendance de production à ce stade ; il reste une piste à auditer, pas une approbation de sécurité.


## 12. Correctifs et validation préparatoire (8 novembre 2026)

- Suppression d'une seconde déclaration dupliquée de `getExisting()` dans `E2eeDeviceIdentity`, qui empêchait l'analyse Dart.
- Sérialisation des créations concurrentes de l'identité d'appareil et de la clé locale de base MLS, à condition que les gestionnaires soient des singletons applicatifs.
- Tests supplémentaires : concurrence de création, séparation des comptes, clé de stockage existante, création, taille invalide et paramètres vides.
- Configuration `flutter_rust_bridge.yaml` ajoutée et génération des bindings épinglée sur `flutter_rust_bridge_codegen 2.13.0`. La CI génère les bindings et publie un artefact de revue ; les bindings générés ne sont pas encore commités ni utilisés par Flutter.
- CI étendue : analyse/tests Dart ciblés, tests Rust hôte, compilation de contrôle Android ARM64 et iOS ARM64.
- Aucun résultat CI n'est présumé : les workflows doivent terminer avant de considérer ces contrôles validés.
- Le crate upstream `openmls_sqlite_storage 0.3.0` fournit un stockage SQLite basé sur rusqlite, mais cela ne signifie pas que la base est chiffrée. Il ne sera pas utilisé tel quel pour les secrets MLS. Il faut intégrer SQLCipher ou un stockage chiffré équivalent, puis tester les transactions et la résistance au rollback.
- Le code de clé Dart est toujours une préparation : la clé de base traverse le tas Dart et ne doit pas être transmise au moteur MLS en production. La prochaine étape doit faire la gestion et la dérivation de la clé dans une frontière native, puis valider le stockage persistant.


## 13. Revue du pipeline CI et décision de stockage (8 novembre 2026)

- La compilation iOS ARM64 OpenMLS a terminé avec succès sur le workflow observé.
- Le job Android a échoué avant toute compilation Rust : l'action Android tentait d'installer l'ancien paquet SDK `tools`, indisponible dans l'image du runner. Le workflow a été corrigé pour accepter les licences et installer directement le NDK 27.2.12479018 avec `sdkmanager --install`. Le résultat du nouveau job doit encore être observé.
- Décision de conception : ne pas envoyer la clé de base depuis Dart au moteur natif. La prochaine implémentation doit créer et conserver la clé de chiffrement dans Rust, puis utiliser Android Keystore/iOS Keychain via une interface native de wrapping/unwrapping, sans exposer la clé déballée à Dart.
- Le stockage SQLite standard ne sera pas assimilé à du stockage chiffré. Évaluer SQLCipher côté Rust (ou une enveloppe AEAD par enregistrement avec authentification des métadonnées et transactions atomiques) et démontrer la résistance à la restauration d'un ancien état avant d'activer MLS.
- Le pont FRB reste une génération/validation CI ; l'intégration des bibliothèques natives dans les paquets Android/iOS et leur initialisation au démarrage restent à faire.
- Aucun flux de messages directs ou communautaires n'est encore chiffré par MLS.


## 14. Premier échange MLS vérifié (8 novembre 2026)

- Ajout de `rust/tests/mls_two_member_flow.rs` avec deux fournisseurs OpenMLS isolés et le ciphersuite MLS 1.0 X25519/AES-128-GCM/SHA-256/Ed25519.
- Le test crée les identités de signature, crée un groupe, publie le KeyPackage de Bob dans le flux de test, ajoute Bob, valide son Welcome, compare les authentificateurs d'époque, chiffre un message applicatif, sérialise/désérialise le message MLS et vérifie le texte après déchiffrement côté Bob.
- Le test retire ensuite Bob, applique le commit de retrait côté Bob, vérifie l'état inactif et vérifie qu'un envoi depuis le membre retiré est refusé.
- Résultat observé sur le job Rust hôte du commit `3066684540dbf350bbd1bad9a6430e92579e3df6` : 2 tests unitaires Rust et 1 test d'intégration MLS réussis ; `cargo check` réussi.
- Le contrôle iOS ARM64 a également terminé avec succès sur ce run. Le contrôle Android ARM64 était encore en cours au moment de la mise à jour.
- L'analyse Dart ciblée a réussi. La suite Flutter avait 10 tests réussis et 1 test échoué à cause du test qui attendait incorrectement une exception synchrone via `expectLater`; le matcher a été corrigé et une nouvelle exécution est en attente.
- Ce test utilise volontairement le fournisseur mémoire OpenMLS. Il prouve l'échange cryptographique, pas la persistance, la protection des clés, la livraison Supabase, la synchronisation multi-appareils, ni la sécurité de production. Le moteur garde `ready_for_messages = false`.


## 15. Intégration de la bibliothèque native Flutter (8 novembre 2026)

- Ajout de `flutter_rust_bridge_hooks: ^2.13.0` et du build hook `hook/build.dart` utilisant `FlutterRustBridgeNativeAssetsBuilder(cratePath: 'rust')`. Le but est de compiler et d'embarquer le crate Rust dans les builds Flutter, et pas seulement de générer des bindings Dart.
- La CI continue de générer les bindings dans un artefact de revue. Le build hook ne rend pas à lui seul les opérations MLS accessibles à Flutter : les bindings générés doivent être intégrés et le chargement natif doit être vérifié dans un APK et une application iOS.
- La vérification Android a identifié une dépendance C native (`dart-sys`) qui ne trouvait pas le compilateur cible. Les variables `CC` et `AR` spécifiques à `aarch64-linux-android` sont désormais exportées en plus du linker NDK. Le prochain run doit confirmer si ce correctif suffit.
- Choix candidat pour la persistance : `openmls_sqlx_storage 0.3.0`, qui est compatible avec `openmls_traits 0.6.0` et prend en charge les transactions SQLx. Ce fournisseur écrit cependant les données via un Codec et ne chiffre pas automatiquement le contenu. Une implémentation de Codec AEAD, avec nonce unique, authentification du type et de la clé de stockage, et effacement effectif des données supprimées, doit être conçue et testée avant de l'adopter.
- OpenMLS considère le stockage comme fiable et recommande une protection d'intégrité/authentification ; sa documentation rappelle également que les suppressions doivent être effectives pour préserver la forward secrecy. Le simple chiffrement de fichiers ou la sauvegarde SQLite ne suffit pas.
- Aucun message de production n'est encore routé vers le moteur ; `ready_for_messages` reste faux.


## 16. Audit des flux applicatifs et enveloppe de transport (8 novembre 2026)

- Audit du dépôt Flutter et du schéma Supabase effectué en lecture seule.
- Le chemin direct actuel appelle `insert_direct_message` avec texte, URL audio et URLs média ; les fonctions de liste renvoient `last_message_text` pour les aperçus. Le cache SQLite direct stocke des objets `Message` et le cache média copie les octets téléchargés en clair.
- La table `community_salon_messages` contient actuellement `content`, `audio_url`, `media_object_key(s)`. Le cache local `salon_chat_local.db` stocke chaque message sous forme de JSON dans `salon_messages.payload`. Les notifications SQL construisent aujourd'hui des aperçus à partir de `community_salon_messages.content`.
- Aucun changement n'a été appliqué au schéma hébergé Supabase. Une note d'audit dédiée détaille les RPC, les caches et le plan de migration.
- Ajout de `E2eeMessageEnvelope`, DTO de transport opaque contenant seulement les identifiants de routage, le groupe, l'appareil expéditeur, l'époque, la version, le ciphersuite et le ciphertext MLS. Le DTO n'expose aucun champ de texte, de prévisualisation ou d'URL média. Le buffer ciphertext est copié à la construction.
- Tests ajoutés pour la sérialisation/désérialisation, le rejet des versions inconnues, des ciphersuites non supportées, des époques négatives et des ciphertexts vides. Le résultat CI de ce nouveau test est en attente.
- Les contrôles CI sur le commit `73661f920fb9ed53b96136892f5bd800d3f5c028` ont réussi pour les tests Rust hôte, la compilation Android ARM64, la compilation iOS ARM64 et les tests/analyse Dart. La génération FRB était encore en cours.
- Une erreur ultérieure dans le workflow Android venait d'un échappement de continuation de ligne mal formé dans la commande `env`; elle a été remplacée par une invocation `env KEY=value ... cargo check` sur une seule ligne. Le run déclenché par le correctif est en attente.
- `rust/rust-toolchain.toml` est maintenant épinglé à Rust 1.91.1, le MSRV d'OpenMLS 0.9, et liste les cibles Android ARM64, iOS ARM64 et Linux host.
- L'enveloppe est une préparation de transport uniquement. Aucune écriture de messages existante n'est routée à travers elle et `ready_for_messages` demeure faux.


## 17. Codec AEAD pour les enregistrements de stockage (8 novembre 2026)

- Ajout de `rust/src/storage_crypto.rs`, module natif interne non exposé à Dart.
- Format versionné `SCM1 || nonce(24 octets) || ciphertext+tag`.
- Chiffrement authentifié XChaCha20-Poly1305 ; un nonce aléatoire neuf est généré à chaque écriture. L'identifiant du slot de stockage est inclus dans les données associées authentifiées pour bloquer les attaques de permutation entre enregistrements.
- La clé est représentée par `StorageKey(Zeroizing<[u8; 32]>)` afin que sa copie native soit effacée à la destruction. Elle n'est pas exposée via FRB.
- Dépendance `chacha20poly1305` épinglée à 0.11.0, release courante au moment de l'implémentation et compatible avec Rust 1.91.1. La crate fournit XChaCha20-Poly1305 et une API AEAD authentifiée.
- Tests unitaires ajoutés : aller-retour, nonce distinct, mauvaise clé, altération, substitution de slot, format invalide.
- Important : ce module est un codec de bas niveau, pas encore un `StorageProvider` OpenMLS. Il n'est pas raccordé à SQLite/SQLx. Le fournisseur complet doit appliquer le codec à chaque valeur et clé sensible, avec transactions atomiques, index non sensibles explicitement justifiés et suppression effective des secrets d'époques expirées.
- Le test CI est en attente ; aucune réussite de compilation n'est revendiquée pour ce nouveau module.
