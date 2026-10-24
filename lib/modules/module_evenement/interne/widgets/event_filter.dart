enum EventSortFilter {
  popularite('Les plus populaires'),
  gratuit('Gratuits'),
  plusAjouts('Les plus ajoutés'),
  plusSurs('Les plus sûrs'),
  proches('Proches de moi');

  final String label;
  const EventSortFilter(this.label);
}
