# Durcissement des fonctionnalités d'événement

La migration `20261021150748_scrole_event_feature_gate_hardening.sql` est appliquée.

- La fonction publique de quotas mobiles inclut `certified_event_horizon_months`.
- Les invitations Guest, sponsors et billets sont bloqués en création, modification et suppression si l'événement n'a pas de certification active.
- Les statistiques financières, la présence par jour et les statistiques du staff exigent une certification active de l'événement, en plus des contrôles existants de propriété/staff.
- Les compteurs publics d'interactions restent disponibles, car ils alimentent l'interface d'engagement publique et ne constituent pas le tableau de statistiques propriétaire.

Valider tous les parcours avec des événements de test avant de considérer la refonte comme entièrement éprouvée.
