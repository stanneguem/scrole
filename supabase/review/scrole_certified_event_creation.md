# Création explicite d'un événement certifié inclus

Cette migration permet à un abonné actif de choisir explicitement une certification d'événement incluse lors de la création. Le serveur vérifie le quota et l'horizon configurés puis attribue la certification dans la même transaction.

- RPC utilisateur : `scrole_get_my_subscription_entitlements()` indique le plan actif, les quotas et les places restantes.
- RPC de création : `create_certified_event_with_subscription(...)` appelle la création existante avec une option transactionnelle; un trigger consomme un quota réel et crée l'entitlement.
- La limite de 6 mois pour un événement certifié reste configurable.
- Un utilisateur ne peut pas contourner le quota en définissant lui-même le paramètre transactionnel : le trigger vérifie abonnement, quota et horizon et consomme la certification.
- Les clients hors ligne doivent utiliser la création ordinaire; la création certifiée exige une réponse serveur afin de ne pas enregistrer localement un événement comme certifié sans confirmation.
