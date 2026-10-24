# Capacités de communauté certifiée

- `get_community_certification_stats(uuid)` fournit au propriétaire les membres, nouveaux membres sur 30 jours, publications actives/récentes, commentaires et réactions; il refuse les communautés non certifiées.
- `link_event_to_community(uuid,uuid)` exige une certification de communauté active et conserve les contrôles de propriété existants.
- La billetterie est autorisée pour un événement certifié ou un événement lié à une communauté certifiée.
- Les invitations Guest, les sponsors et les statistiques d'événement restent réservés à une certification d'événement. Une communauté certifiée ne transforme pas automatiquement l'événement en événement certifié.
