/// Modèle unifié léger pour les résultats de la RPC search_all.
class SearchResultItem {
  final String category;
  final String id;
  final String title;
  final String? subtitle;
  final String? photoUrl;
  final int? friendCount;
  final bool isCertified;
  final bool followsMe;

  const SearchResultItem({
    required this.category,
    required this.id,
    required this.title,
    this.subtitle,
    this.photoUrl,
    this.friendCount,
    this.isCertified = false,
    this.followsMe = false,
  });

  factory SearchResultItem.fromJson(Map<String, dynamic> json) {
    return SearchResultItem(
      category: json['category']?.toString() ?? '',
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      subtitle: json['subtitle']?.toString(),
      photoUrl: json['photo_url']?.toString(),
      friendCount: (json['friend_count'] as num?)?.toInt(),
      isCertified: json['is_certified'] == true || json['is_verified'] == true || json['is_certified'] == 1 || json['is_verified'] == 1,
      followsMe: json['follows_me'] == true,
    );
  }
}

/// Suggestion de compte (utilisateur) affichée dans l'onglet "Comptes".
class AccountSuggestion {
  final String id;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final String? bio;
  final bool isVerified;
  final int? friendCount;
  final bool followsMe;

  const AccountSuggestion({
    required this.id,
    required this.username,
    required this.displayName,
    this.avatarUrl,
    this.bio,
    this.isVerified = false,
    this.friendCount,
    this.followsMe = false,
  });
}

/// Suggestion de communauté affichée dans l'onglet "Communautés".
class CommunitySuggestion {
  final String id;
  final String name;
  final String? imageUrl;
  final String? description;
  final int membersCount;

  const CommunitySuggestion({
    required this.id,
    required this.name,
    this.imageUrl,
    this.description,
    this.membersCount = 0,
  });
}

/// Modèle pour les cartes de communautés style Pinterest à l'état idle.
class MockCommunity {
  final String id;
  final String name;
  final String category;
  final String bannerUrl;
  final String avatarUrl;
  final int membersCount;
  final double cardHeight;

  const MockCommunity({
    required this.id,
    required this.name,
    required this.category,
    required this.bannerUrl,
    required this.avatarUrl,
    required this.membersCount,
    this.cardHeight = 220.0,
  });
}

const mockPinterestCommunities = [
  MockCommunity(
    id: 'm1',
    name: 'Kamer Manga & Otaku Club',
    category: 'Otaku',
    bannerUrl: 'https://images.unsplash.com/photo-1578632767115-351597cf2477?w=600&auto=format&fit=crop',
    avatarUrl: 'https://api.dicebear.com/7.x/avataaars/png?seed=OtakuKamer',
    membersCount: 4820,
    cardHeight: 260.0,
  ),
  MockCommunity(
    id: 'm2',
    name: 'Yaoundé Tech & Code',
    category: 'Tech',
    bannerUrl: 'https://images.unsplash.com/photo-1526374965328-7f61d4dc18c5?w=600&auto=format&fit=crop',
    avatarUrl: 'https://api.dicebear.com/7.x/identicon/png?seed=TechCM',
    membersCount: 2150,
    cardHeight: 200.0,
  ),
  MockCommunity(
    id: 'm3',
    name: 'Afro Gaming & eSport',
    category: 'Gaming',
    bannerUrl: 'https://images.unsplash.com/photo-1538481199705-c710c4e965fc?w=600&auto=format&fit=crop',
    avatarUrl: 'https://api.dicebear.com/7.x/bottts/png?seed=AfroGame',
    membersCount: 6300,
    cardHeight: 240.0,
  ),
  MockCommunity(
    id: 'm4',
    name: 'Cameroun Music & Beats',
    category: 'Musique',
    bannerUrl: 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=600&auto=format&fit=crop',
    avatarUrl: 'https://api.dicebear.com/7.x/avataaars/png?seed=MusicCM',
    membersCount: 3400,
    cardHeight: 190.0,
  ),
  MockCommunity(
    id: 'm5',
    name: 'Digital Art & Design Africa',
    category: 'Art',
    bannerUrl: 'https://images.unsplash.com/photo-1579783902614-a3fb3927b675?w=600&auto=format&fit=crop',
    avatarUrl: 'https://api.dicebear.com/7.x/identicon/png?seed=PixelArt',
    membersCount: 1890,
    cardHeight: 270.0,
  ),
  MockCommunity(
    id: 'm6',
    name: 'Douala Business Hub',
    category: 'Business',
    bannerUrl: 'https://images.unsplash.com/photo-1522071820081-009f0129c71c?w=600&auto=format&fit=crop',
    avatarUrl: 'https://api.dicebear.com/7.x/avataaars/png?seed=DoualaBiz',
    membersCount: 2980,
    cardHeight: 220.0,
  ),
  MockCommunity(
    id: 'm7',
    name: 'Photographie & Cinéma CM',
    category: 'Cinéma',
    bannerUrl: 'https://images.unsplash.com/photo-1485846234645-a62644f84728?w=600&auto=format&fit=crop',
    avatarUrl: 'https://api.dicebear.com/7.x/identicon/png?seed=PhotoCM',
    membersCount: 1420,
    cardHeight: 230.0,
  ),
  MockCommunity(
    id: 'm8',
    name: 'Fitness & Running Club',
    category: 'Sport',
    bannerUrl: 'https://images.unsplash.com/photo-1517838277536-f5f99be501cd?w=600&auto=format&fit=crop',
    avatarUrl: 'https://api.dicebear.com/7.x/avataaars/png?seed=FitnessCM',
    membersCount: 950,
    cardHeight: 200.0,
  ),
];

/// Les 4 états possibles de l'écran Discover.
enum DiscoverState { idle, loading, error, found }

/// Les 3 onglets de résultats une fois une recherche effectuée.
enum DiscoverTab { comptes, evenements, communautes }
