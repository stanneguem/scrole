import 'package:get/get.dart';

enum EventSortFilter {
  popularite('event_sort_popularity'),
  gratuit('event_sort_free_first'),
  plusAjouts('event_sort_most_added'),
  plusSurs('event_sort_checkins'),
  proches('event_sort_date');

  final String translationKey;
  const EventSortFilter(this.translationKey);

  String get label => translationKey.tr;
}

enum EventCalendarFilter {
  tous('event_calendar_filter_all'),
  aVenir('event_calendar_filter_upcoming'),
  gratuits('event_calendar_filter_free'),
  payants('event_calendar_filter_paid'),
  enLigne('event_calendar_filter_online'),
  enPresentiel('event_calendar_filter_in_person');

  final String translationKey;
  const EventCalendarFilter(this.translationKey);

  String get label => translationKey.tr;
}
