/// Maximum number of media items allowed in one post (photos + videos combined).
/// Keep this value aligned with the create_post RPC and the database constraint.
const int maxPostMedia = 20;

/// Maximum number of photos allowed by the post composer.
/// Photos also count toward [maxPostMedia], so a post cannot exceed 20 total items.
const int maxPostPhotos = 20;
