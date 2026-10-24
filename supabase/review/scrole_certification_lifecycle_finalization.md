# Finalisation du cycle de vie

La migration `20261021150602_scrole_certification_lifecycle_finalization.sql` est appliquée.

- Ajoute le quota administrable `certified_event_horizon_months` (valeur initiale : 6 mois).
- Un événement doit avoir sa propre certification active; la certification Pro/Premium du profil ou de la communauté ne le certifie pas automatiquement.
- `scrole_grant_included_certification` et `scrole_grant_included_profile_certification` sont accessibles uniquement à `service_role`, après validation côté serveur de l'abonnement/paiement.
- À l'expiration, les certifications incluses sont suspendues, non supprimées; l'historique est conservé.
- `pg_cron` exécute `scrole_suspend_expired_subscription_certifications()` toutes les 15 minutes.
- Un index partiel empêche plusieurs abonnements actifs pour un même utilisateur.

Le vrai prestataire de paiement et les parcours d'activation/renouvellement doivent encore être intégrés et testés avant la production complète.
