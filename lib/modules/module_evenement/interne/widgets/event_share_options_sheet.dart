import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:scrole/app/theme/app_colors.dart';
import 'package:scrole/modules/module_evenement/centre/models/event_preview_model.dart';
import 'package:scrole/modules/module_communautes/externe/repositories/community_repository.dart';
import 'package:scrole/shared/widgets/entity_certified_badge.dart';

class EventShareOptionsSheet extends StatelessWidget {
  const EventShareOptionsSheet({
    super.key,
    required this.preview,
    required this.onFeed,
    required this.onCommunity,
    required this.onStory,
    required this.onNativeApps,
  });

  final EventPreviewModel preview;
  final VoidCallback onFeed;
  final VoidCallback onCommunity;
  final VoidCallback onStory;
  final VoidCallback onNativeApps;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final event = preview.event;

    return Container(
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).padding.bottom + 24),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colors.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Partager l’événement',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: colors.onSurface),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                if (event.coverImageUrl != null && event.coverImageUrl!.isNotEmpty) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      event.coverImageUrl!,
                      width: 52,
                      height: 52,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _eventIcon(colors),
                    ),
                  ),
                  const SizedBox(width: 12),
                ] else ...[
                  _eventIcon(colors),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              event.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: colors.onSurface),
                            ),
                          ),
                          EntityCertifiedBadge(entityType: 'event', entityId: event.id, size: 16),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        [
                          MaterialLocalizations.of(context).formatMediumDate(event.startsAt),
                          if ((event.city?.name ?? '').trim().isNotEmpty) event.city!.name.trim(),
                        ].join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Destinations',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _EventShareOption(
                  svgAsset: 'assets/svg_icons/story-svgrepo-com.svg',
                  color: Colors.pink,
                  label: 'Ma story',
                  onTap: onStory,
                ),
                const SizedBox(width: 16),
                _EventShareOption(
                  svgAsset: 'assets/svg_icons/repost-round-svgrepo-com.svg',
                  color: colors.primary,
                  label: 'Mon fil',
                  onTap: onFeed,
                ),
                const SizedBox(width: 16),
                _EventShareOption(
                  svgAsset: 'assets/svg_icons/ecosystem-svgrepo-com.svg',
                  color: Colors.purple,
                  label: 'Communauté',
                  onTap: onCommunity,
                ),
                const SizedBox(width: 16),
                _EventShareOption(
                  icon: Icons.ios_share_rounded,
                  color: Colors.green,
                  label: 'Autres apps',
                  onTap: onNativeApps,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _eventIcon(ColorScheme colors) => Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: const Icon(Icons.event_rounded, color: AppColors.primary, size: 26),
      );
}

class _EventShareOption extends StatelessWidget {
  const _EventShareOption({
    this.icon,
    this.svgAsset,
    required this.color,
    required this.label,
    required this.onTap,
  });

  final IconData? icon;
  final String? svgAsset;
  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 76,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
                border: Border.all(color: color.withValues(alpha: 0.3)),
              ),
              alignment: Alignment.center,
              child: svgAsset != null
                  ? SvgPicture.asset(
                      svgAsset!,
                      width: 26,
                      height: 26,
                      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
                    )
                  : Icon(icon, color: color, size: 26),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colors.onSurface),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class EventShareCommunityPicker extends StatefulWidget {
  const EventShareCommunityPicker({super.key, required this.onSelected});

  final ValueChanged<Map<String, dynamic>> onSelected;

  @override
  State<EventShareCommunityPicker> createState() => _EventShareCommunityPickerState();
}

class _EventShareCommunityPickerState extends State<EventShareCommunityPicker> {
  bool _loading = true;
  List<Map<String, dynamic>> _communities = [];
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadCommunities();
  }

  Future<void> _loadCommunities() async {
    try {
      final result = await CommunityRepository().getMyCommunities();
      if (mounted) {
        setState(() {
          _communities = result;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('[EventShareCommunityPicker] Failed to load communities: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final filtered = _communities.where((community) {
      final name = (community['name'] ?? '').toString().toLowerCase();
      return name.contains(_query.trim().toLowerCase());
    }).toList();

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.72),
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).padding.bottom + 20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Partager dans une communauté', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: colors.onSurface)),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const Divider(height: 1),
          const SizedBox(height: 12),
          TextField(
            onChanged: (value) => setState(() => _query = value),
            decoration: InputDecoration(
              hintText: 'Rechercher une communauté…',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          ),
          const SizedBox(height: 12),
          if (_loading)
            const SizedBox(height: 140, child: Center(child: CircularProgressIndicator()))
          else if (filtered.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Text('Aucune communauté trouvée.', textAlign: TextAlign.center),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
                  final community = filtered[index];
                  final name = (community['name'] ?? 'Communauté').toString();
                  final avatar = (community['photo_profile'] ?? community['avatar_url'] ?? '').toString();
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: colors.primary.withValues(alpha: 0.12),
                      backgroundImage: avatar.isNotEmpty ? NetworkImage(avatar) : null,
                      child: avatar.isEmpty ? Icon(Icons.groups_rounded, color: colors.primary) : null,
                    ),
                    title: Row(children: [Flexible(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis)), EntityCertifiedBadge(entityType: 'community', entityId: (community['id'] ?? '').toString(), size: 16)]),
                    trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                    onTap: () => widget.onSelected(community),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
