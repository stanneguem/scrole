# Audit des flux de messagerie avant activation E2EE

Date: 8 novembre 2026
Branche examinée: `feature/story-video-post-reshare`

## Décision

Conserver OpenMLS / MLS (RFC 9420) comme protocole de groupe commun aux conversations directes et aux salons communautaires. Ne pas ajouter un protocole direct distinct de type Signal tant que MLS peut couvrir les deux cas : cela évite deux formats cryptographiques, deux mécanismes de multi-appareils et deux procédures de révocation à maintenir.

Le backend Supabase devient un service de livraison opaque pour les contenus E2EE. Il conserve les identifiants, l'ordre, les horodatages, les accusés de réception, les droits d'accès et les événements de synchronisation, mais ne doit plus calculer de prévisualisation textuelle ni accéder au contenu déchiffré.

## Flux directs observés

- `SupabaseMessagingService.insertMessage()` appelle le RPC `insert_direct_message` avec le texte, le type, l'URL audio, les URLs média et le message auquel on répond.
- `fetchMessages()` et `fetchMissedMessages()` utilisent `get_direct_messages` et `get_direct_messages_after`.
- `fetchConversations()` consomme `get_my_direct_conversations` et reçoit `last_message_text`, donc un aperçu potentiellement en clair.
- Les modifications et suppressions passent par `edit_direct_message` et `delete_direct_message`.
- Les notifications FCM réveillent la synchronisation. Les notifications visibles et leurs données doivent être neutralisées pour ne jamais contenir de texte de message, même quand l'app est en arrière-plan.
- Le modèle Flutter `Message` ne contient actuellement que `content`, `mediaUrls` et `audioUrl`; il faudra un modèle de transport séparé avec `ciphertext`, `protocol_version`, `group_id`, `epoch`, `sender_device_id`, `message_kind` et des métadonnées authentifiées minimales.

## Cache local direct

- Les messages sont conservés dans `direct_chat_messages` via `MessagesDao`.
- Les médias téléchargés sont copiés dans le répertoire privé de l'application par `MediaLocalCache`, mais restent des fichiers lisibles en clair.
- L'outbox et les aperçus de conversation doivent être audités en détail avant migration : ils ne doivent pas sérialiser le texte déchiffré dans les journaux, les bases SQLite ou les états de reprise.

## Salons communautaires observés

- La base Supabase `community_salon_messages` contient actuellement `content`, `audio_url`, `media_object_key` et `media_object_keys`.
- La synchronisation est paginée par `get_salon_messages_since` et `get_salon_message_delta`.
- Le cache local dédié `salon_chat_local.db` stocke le message entier sous forme de JSON dans `salon_messages.payload`. Ce cache est donc explicitement en clair aujourd'hui.
- Dans le code Flutter de cette branche, le module Communautés contient la base/cache des salons et les écrans de gestion des salons, mais aucun dépôt/service de livraison des messages de salon n'apparaît dans l'arborescence examinée. La branche ne doit pas être considérée comme ayant un chemin client de salon prêt pour E2EE.
- Le membership serveur existant est une base utile pour autoriser l'accès au transport, mais il ne remplace pas la liste cryptographique MLS des membres.

## Schéma Supabase constaté (lecture seule)

- `direct_messages`: `text`, `type`, `audio_url`, `media_urls`, `replied_to_id`, timestamps et marqueurs de suppression/édition.
- `direct_conversations`: les deux identifiants participants et les horodatages.
- `community_salon_messages`: `content`, `type`, `audio_url`, `media_object_key(s)`, `replied_to_id`, timestamps et marqueurs de suppression.
- `community_salon_members`: `salon_id`, `user_id`, rôle et `joined_at`.

Aucune modification de schéma n'a été appliquée à Supabase pendant cet audit.

## Évolution de transport recommandée

Ajouter une enveloppe commune de message chiffré, sans réutiliser les colonnes texte historiques comme conteneurs implicites :

- identifiant de message stable généré côté client ;
- identifiant de conversation/salon ;
- version du protocole et ciphersuite ;
- identifiant du groupe MLS et époque ;
- identifiant public du device expéditeur ;
- bytes MLS sérialisés (base64 uniquement si le RPC JSON l'impose ; privilégier un transport binaire lorsque le service le supporte) ;
- type de contenu opaque et métadonnées non sensibles nécessaires à l'affichage ;
- liens média opaques vers les objets chiffrés.

Les fonctions RPC de transport doivent vérifier l'identité et l'appartenance, stocker/relayer les bytes sans déchiffrement, et retourner les mêmes bytes aux membres autorisés. Ne pas accepter de client qui écrit un champ chiffré mais laisse simultanément le texte en clair.

## Médias

Le chiffrement doit avoir lieu sur l'appareil avant tout téléversement R2. Chaque média doit utiliser une clé aléatoire dédiée et un format de fichier versionné avec nonce, tag AEAD et identifiant de clé. Le secret de média doit être transporté uniquement dans l'enveloppe MLS du message. R2 ne reçoit que des octets chiffrés. Le cache local conserve aussi le média chiffré; le déchiffrement ne se fait qu'à l'ouverture/lecture.

## Migration et coexistence

- Ne jamais prétendre que l'historique existant est E2EE. Les anciens messages restent consultables dans leur format historique tant que l'utilisateur ne les migre pas par une action explicite.
- Ajouter un marqueur de conversation `encryption_mode` et une version de schéma/protocole. L'activation est explicite par conversation, avec tous les appareils participants enregistrés et des KeyPackages valides.
- Une conversation ne bascule en mode MLS qu'après un commit MLS initial confirmé par les appareils requis. Les messages postérieurs sont chiffrés ; les anciens restent identifiés comme legacy.
- En cas d'appareil retiré, appliquer un commit Remove et ne pas lui transmettre le nouvel epoch secret. Un nouveau device rejoint par Welcome approuvé, jamais par copie d'un secret existant non authentifié.
- Les groupes communautaires nécessitent un processus fiable de synchronisation des membres serveur vers les commits MLS, avec gestion des courses d'ajout/retrait et des membres en attente.

## Dépendances bloquantes avant raccordement

1. Terminer la génération FRB et vérifier les artefacts natifs Android/iOS.
2. Implémenter un stockage OpenMLS persistant avec codec AEAD, transactions atomiques et politique de suppression des secrets d'époques passées.
3. Déplacer la gestion des clés de wrapping dans une frontière native adossée au Keystore/Keychain. Ne pas renvoyer de clé de base en clair à l'application Dart.
4. Créer le cycle de vie Device/KeyPackage/Welcome/Commit côté client et serveur.
5. Adapter les modèles, caches SQLite, outbox, prévisualisations, push, RPC et médias.
6. Tester deux appareils par compte, plusieurs participants, rejoin, retrait, restauration, corruption/rollback et perte d'appareil.

## État de sécurité

Le moteur annonce toujours `ready_for_messages = false`. Le test Rust deux membres prouve le chiffrement/déchiffrement et le retrait en mémoire seulement. Il ne prouve pas la persistance, le transport Supabase, la sécurité du cache local ou le multi-appareils.


## Transport et sécurité serveur mis à jour

Les migrations `20261108240000` à `20261108244000` ont été appliquées au projet Supabase actif. Les groupes et messages MLS sont des tables séparées des messages legacy ; RLS n'autorise la lecture qu'aux appareils membres qui restent autorisés dans la conversation/salon. Les RPC d'envoi n'acceptent que des bytes ciphertext et n'écrivent aucun aperçu.

Le dépôt Flutter `E2eeTransportRepository` appelle ces RPC, mais il reste volontairement isolé des écrans legacy jusqu'à ce que le moteur OpenMLS natif fournisse des messages chiffrés et déchiffrés réels. La présence de la table de transport ne signifie pas que les conversations actuelles sont E2EE.
