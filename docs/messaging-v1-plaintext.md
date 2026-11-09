# Messagerie Scrole — version 1

## Décision produit

Pour Scrole V1, les conversations directes et les salons communautaires utilisent le transport historique en clair :
- messages directs : `direct_messages.text` ;
- messages des salons : `community_salon_messages.content`.

Aucun chiffrement de bout en bout (E2EE/MLS) n'est appliqué par les clients mobile ou Web. Les clients envoient et affichent le texte normal via les services Supabase existants. Les médias de messagerie suivent également le flux de stockage actuel et ne sont pas chiffrés côté client.

## Conséquences de sécurité

Le chiffrement TLS protège le transport réseau, mais le contenu des messages est lisible par les services backend et les personnes disposant des accès autorisés à la base. Les contrôles d'accès Supabase, les politiques RLS, les autorisations de conversation/salon et la sécurité des comptes restent obligatoires. Ne jamais exposer la clé `service_role` dans un client mobile ou navigateur.

## Périmètre technique

Le prototype OpenMLS/Rust et les tables Supabase `e2ee_*` sont désactivés et non utilisés par les flux de messagerie V1. Ils sont conservés comme référence pour une éventuelle V2, mais ne sont ni construits ni appelés par l'application V1. Les tables E2EE existantes sont vides ; elles ne sont pas supprimées afin d'éviter une migration destructive et de préserver la possibilité d'une évolution ultérieure.

Toute réactivation future de l'E2EE devra être une décision de version distincte, avec une migration explicite, une compatibilité de messages et des tests multi-appareils.
