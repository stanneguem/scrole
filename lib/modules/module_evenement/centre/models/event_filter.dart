enum EventFilter {
  popularite('Popularité'),
  enthousiasme('Enthousiasme'),
  date('Date'),
  proximite('Proximité');

  final String label;
  const EventFilter(this.label);
}