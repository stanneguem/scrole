class FastCacheKey {
  static const String profile = "profile";
  static const String activities = "activities";
  static const String userActivities = "user_activities";
  static const String interests = "interests";
  static const String communities = "communities";

  static String userProfile(String userId) => "profile_$userId";
  static String externalProfile(String userId) => "external_profile_$userId";
  static String activityDetail(String activityId) => "activity_$activityId";
  static String userActivitiesList(String userId) => "user_activities_$userId";
  static String communityDetail(String communityId) => "community_$communityId";

  static const String userCachePrefix = "user_";
  static const String activityCachePrefix = "activity_";
  static const String communityCachePrefix = "community_";
}