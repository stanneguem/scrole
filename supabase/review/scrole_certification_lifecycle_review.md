# Scrole — cycle de vie des certifications

La migration `20261021150308_scrole_certification_lifecycle_and_feature_gates.sql` est appliquée.

- Les événements non certifiés sont soumis à leurs limites configurées; les événements certifiés ont un horizon propre.
- Les certifications d'événement, de communauté et de profil incluses dans l'abonnement sont distinguées des certifications acquises indépendamment.
- Les fonctions de renouvellement et d'attribution d'entitlements inclus sont réservées à `service_role`.
- Le passage Premium → Pro utilise `scrole_change_subscription_plan_v2` pour sélectionner plusieurs entités selon les quotas actuellement configurés; les autres entitlements inclus sont suspendus, jamais supprimés.
- La fonction d'expiration suspend les certifications incluses et conserve leur historique. Le profil inclus est synchronisé via `profile_certification_entitlements`.
- Les invitations Guest et sponsors sont réservées aux événements ayant une certification d'événement active; la billetterie accepte aussi une communauté certifiée liée.
- Les statistiques de l'événement, de présence par jour, financières et du staff sont protégées par la certification d'événement.

- La création peut consommer explicitement un événement inclus via `create_certified_event_with_subscription`; le quota est contrôlé et consommé dans la transaction.
- Les communautés certifiées disposent d'une RPC de statistiques réservée au propriétaire et peuvent être reliées aux événements pour activer la billetterie. Cela ne certifie pas l'événement lui-même.

## Avant production
- Relier les RPC d'attribution et de renouvellement au véritable prestataire de paiement/webhook.
- Tester avec des comptes de test : expiration, renouvellement, downgrade, quota augmenté, droits et absence de doublons.
- L'interface de sélection des entitlements lors d'un downgrade doit gérer plusieurs choix si l'administration augmente les quotas au-delà des valeurs actuelles.
- Tester les suppressions/modifications d'invitations/tickets après suspension de certification, car les gates s'appliquent également à ces opérations.
