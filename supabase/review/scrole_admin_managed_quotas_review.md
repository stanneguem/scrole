# Scrole — quotas administrables

La migration `20261021150100_scrole_admin_managed_quotas.sql` est appliquée au projet Supabase et son nom/version correspond à l'historique distant.

## Quotas initiaux
- Agenda d'un profil sans certification active : 2 événements et un horizon de 2 mois.
- Événement non certifié : horizon de 2 mois, durée maximale de 2 jours, 100 ajouts à l'agenda.
- Événement non certifié : 1 cofondateur (en plus du fondateur) et 5 membres du personnel.
- Événement certifié : horizon de 6 mois.
- Pro : 1 événement certifié et 1 communauté certifiée inclus.
- Premium : 4 événements certifiés et 4 communautés certifiées inclus.

Toutes les valeurs sont stockées dans `scrole_quota_settings`, affichées dans la page d'administration web et modifiables par RPC sécurisée.

## Sécurité
- RLS est activé; la table de quotas n'accorde pas de lecture/écriture directe à `anon` ou `authenticated`.
- Lecture par `admin_get_scrole_quotas()`; modification par `admin_update_scrole_quota(key,value)`.
- Seuls les super-admins ou les administrateurs disposant de `certifications.manage` peuvent modifier les quotas.
- Les modifications sont inscrites dans `scrole_certification_audit`.
- Les triggers serveur appliquent les limites agenda, dates/durées et équipe indépendamment du front.

## Sémantique
La certification de profil retire uniquement les limites personnelles de l'agenda. Elle ne certifie pas les événements créés. Une certification de communauté ne certifie pas non plus automatiquement ses événements; la certification de l'événement est indépendante.
