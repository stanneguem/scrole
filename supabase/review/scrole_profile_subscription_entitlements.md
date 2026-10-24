# Profile certification subscription provenance

This migration adds explicit provenance to `user_certifications` so an included Pro/Premium profile certification can be suspended/reactivated without deleting the row or affecting independently acquired certifications.

- Existing rows retain `source='request'` and their non-null request ID.
- Only `source='subscription_included'` rows may have a null request ID; these must have a valid subscription ID.
- The service-role grant RPC now uses the existing default certification-code generator and creates a profile entitlement linked to the subscription.
- The subscription lifecycle trigger synchronizes the profile tier on downgrade and its validity on expiry/renewal.

No existing certification rows are deleted. Test insertion, expiration, renewal, independent certification preservation and profile badge resolution on a disposable project before production rollout.
