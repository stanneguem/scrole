import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../centre/repositories/event_repository.dart';
import '../../../../app/routes/app_pages.dart';
import '../../interne/pages/event_detail_page.dart';
import '../../interne/pages/event_comments_screen.dart';
import '../../interne/pages/event_itinerary_overview_screen.dart';
import '../../interne/pages/external_event_itinerary_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../centre/models/event_model.dart';
import '../../../../shared/widgets/app_cached_image.dart';
import '../../../module_principale/centre/models/community_post.dart';
import '../../../module_principale/interne/widgets/feed_post_card.dart';
import '../../../module_principale/externe/repositories/home_feed_repository.dart';

class ProfileEventSeriesScreen extends StatelessWidget {
  final Map<String, dynamic> series;
  final String profileUserId;
  final bool ownerMode;
  const ProfileEventSeriesScreen({
    super.key,
    required this.series,
    required this.profileUserId,
    this.ownerMode = false,
  });

  Future<void> _openEdition(BuildContext context, Map<String, dynamic> edition) async {
    final id = (edition['id'] ?? '').toString();
    if (id.isEmpty) return;
    try {
      if (ownerMode) {
        Get.toNamed(
          AppPages.eventPreview.replaceFirst(':id', id),
          arguments: {'id': id, 'context': 'owner'},
        );
      } else {
        final event = await Get.find<EventRepository>().getEventById(id);
        if (context.mounted) Get.to(() => ArchivedEventEditionScreen(event: event, profileUserId: profileUserId));
      }
    } catch (_) {
      Get.snackbar('Événement', 'Impossible de charger cette édition.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final raw = series['editions'];
    final editions = raw is List
        ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : <Map<String, dynamic>>[];
    editions.sort((a, b) => ((b['edition_number'] as num?)?.toInt() ?? 1)
        .compareTo((a['edition_number'] as num?)?.toInt() ?? 1));
    return Scaffold(
      appBar: AppBar(title: Text((series['name'] ?? 'Événement').toString(),
        maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: editions.isEmpty
          ? Center(child: Text('Aucune édition disponible', style: TextStyle(color: colors.onSurfaceVariant)))
          : GridView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: editions.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.78,
              ),
              itemBuilder: (context, index) {
                final edition = editions[index];
                final image = (edition['photo'] ?? edition['photo_url'] ?? edition['cover_image_url'] ?? '').toString();
                final number = (edition['edition_number'] as num?)?.toInt() ?? 1;
                final start = DateTime.tryParse((edition['starts_at'] ?? edition['date_debut'] ?? '').toString());
                final date = start == null
                    ? ''
                    : '${start.day.toString().padLeft(2, '0')}/${start.month.toString().padLeft(2, '0')}/${start.year}';
                final city = (edition['city'] ?? edition['address'] ?? edition['adresse'] ?? '').toString();
                return Material(
                  color: colors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(16),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => _openEdition(context, edition),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (image.isNotEmpty)
                                AppCachedImage(imageUrl: image, fit: BoxFit.cover)
                              else
                                Container(
                                  color: colors.surfaceContainerHighest,
                                  child: Icon(Icons.event_rounded,
                                      size: 42, color: colors.onSurfaceVariant),
                                ),
                              Positioned(
                                top: 10,
                                left: 10,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.68),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 6),
                                    child: Text(
                                      'Édition $number',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(11, 10, 11, 11),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (date.isNotEmpty)
                                Text(
                                  date,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: colors.onSurface,
                                  ),
                                ),
                              if (city.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(Icons.location_on_outlined,
                                        size: 13, color: colors.onSurfaceVariant),
                                    const SizedBox(width: 3),
                                    Expanded(
                                      child: Text(
                                        city,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: colors.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            )
    );
  }
}


class ArchivedEventEditionScreen extends StatelessWidget {
  final EventModel event;
  final String profileUserId;
  const ArchivedEventEditionScreen({super.key, required this.event, required this.profileUserId});

  void _openProgram() {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id ?? '';
    if (currentUserId == profileUserId) {
      Get.to(() => EventItineraryOverviewScreen(event: event, readOnly: true));
    } else {
      Get.to(() => ExternalEventItineraryScreen(
        userId: profileUserId,
        eventId: event.id,
        eventName: event.name,
        eventPhoto: event.coverImageUrl ?? '',
        eventLocation: event.locationDisplay,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(event.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(
              tooltip: 'Commentaires',
              onPressed: () => Get.to(() => EventCommentsScreen(eventId: event.id, eventName: event.name)),
              icon: const Icon(Icons.chat_bubble_outline_rounded),
            ),
            IconButton(
              tooltip: 'Revoir mon programme',
              onPressed: _openProgram,
              icon: const Icon(Icons.route_rounded),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.photo_library_outlined), text: 'Galerie'),
              Tab(icon: Icon(Icons.info_outline_rounded), text: 'Détails'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _ArchivedEventGallery(eventId: event.id),
            EventDetailPage(event: event, profileUserId: profileUserId, archiveTabMode: true),
          ],
        ),
      ),
    );
  }
}

Future<void> openProfileEventSeries(BuildContext context, Map<String, dynamic> series, {required String profileUserId}) async {
  final raw = series['editions'];
  final editions = raw is List
      ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : <Map<String, dynamic>>[];
  if (editions.length == 1) {
    final id = (editions.first['id'] ?? '').toString();
    if (id.isEmpty) return;
    try {
      final event = await Get.find<EventRepository>().getEventById(id);
      if (context.mounted) Get.to(() => ArchivedEventEditionScreen(event: event, profileUserId: profileUserId));
    } catch (_) {
      Get.snackbar('Événement', 'Impossible de charger cette édition.');
    }
    return;
  }
  if (context.mounted) Get.to(() => ProfileEventSeriesScreen(series: series, profileUserId: profileUserId));
}


/// Charge uniquement les publications explicitement associées à cette édition.
/// get_post fournit le même payload enrichi que celui utilisé par le fil d'actualité
/// (auteur, médias, réactions et compteurs) tout en respectant les règles d'accès.
class _ArchivedEventGallery extends StatefulWidget {
  final String eventId;
  const _ArchivedEventGallery({required this.eventId});

  @override
  State<_ArchivedEventGallery> createState() => _ArchivedEventGalleryState();
}

class _ArchivedEventGalleryState extends State<_ArchivedEventGallery> {
  late Future<List<CommunityPost>> _postsFuture;

  @override
  void initState() {
    super.initState();
    _postsFuture = _loadPosts();
  }

  @override
  void didUpdateWidget(covariant _ArchivedEventGallery oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.eventId != widget.eventId) {
      _postsFuture = _loadPosts();
    }
  }

  Future<List<CommunityPost>> _loadPosts() async {
    final client = Supabase.instance.client;
    final links = await client
        .from('event_post_links')
        .select('post_id, created_at')
        .eq('event_id', widget.eventId)
        .order('created_at', ascending: false);

    final postIds = links
        .whereType<Map>()
        .map((row) => row['post_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();

    if (postIds.isEmpty) return [];

    final repository = HomeFeedRepository(client);
    final results = await Future.wait(
      postIds.map((id) async {
        try {
          return await repository.getPost(id);
        } catch (error) {
          debugPrint('[ArchivedEventGallery] post $id unavailable: $error');
          return null;
        }
      }),
    );

    return results.whereType<CommunityPost>().toList();
  }

  Future<void> _refresh() async {
    setState(() => _postsFuture = _loadPosts());
    await _postsFuture;
  }

  Future<void> _react(CommunityPost post, PostReaction reaction) async {
    final repository = HomeFeedRepository();
    try {
      if (reaction == PostReaction.none) {
        await repository.removeCommunityPostReaction(post.id);
      } else {
        await repository.reactToCommunityPost(
          post.id,
          reaction == PostReaction.like ? 'like' : 'dislike',
        );
      }
      await _refresh();
    } catch (error) {
      Get.snackbar('Publication', 'Impossible d’enregistrer cette réaction.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return FutureBuilder<List<CommunityPost>>(
      future: _postsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cloud_off_outlined, size: 40, color: colors.onSurfaceVariant),
                  const SizedBox(height: 12),
                  const Text('Impossible de charger les publications de cette édition.'),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Réessayer'),
                  ),
                ],
              ),
            ),
          );
        }

        final posts = snapshot.data ?? const <CommunityPost>[];
        if (posts.isEmpty) {
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 110),
                Icon(Icons.photo_library_outlined, size: 46, color: colors.onSurfaceVariant),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    'Aucune publication pour cette édition',
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: posts.length,
            itemBuilder: (context, index) {
              final post = posts[index];
              return FeedPostCard(
                post: post,
                onReactionTap: (reaction) => _react(post, reaction),
                onCommentTap: () => Get.toNamed(
                  '/post-comments',
                  arguments: {'postId': post.id},
                ),
                onShareTap: null,
                margin: EdgeInsets.zero,
              );
            },
          ),
        );
      },
    );
  }
}
