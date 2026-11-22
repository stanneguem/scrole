import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:scrole/app/theme/app_colors.dart';
import 'package:scrole/app/theme/text_styles.dart';
import 'package:scrole/modules/module_communautes/centre/models/news/community_hashtag.dart';
import 'package:scrole/modules/module_communautes/centre/services/community_service.dart';
import 'package:scrole/modules/module_communautes/interne/controllers/community/community_feed_controller.dart';

class CommunityPostHashtagSelectionScreen extends StatefulWidget {
  final List<CommunityHashtag> initialSelected;

  const CommunityPostHashtagSelectionScreen({
    super.key,
    this.initialSelected = const [],
  });

  @override
  State<CommunityPostHashtagSelectionScreen> createState() => _CommunityPostHashtagSelectionScreenState();
}

class _CommunityPostHashtagSelectionScreenState extends State<CommunityPostHashtagSelectionScreen> {
  late final List<CommunityHashtag> _selected;
  final TextEditingController _searchController = TextEditingController();
  List<CommunityHashtag> _searchResults = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _selected = List.from(widget.initialSelected);
    _searchHashtags('');
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _searchHashtags(String query) async {
    try {
      setState(() => _isLoading = true);
      final feedController = Get.isRegistered<CommunityFeedController>()
          ? Get.find<CommunityFeedController>()
          : Get.put(CommunityFeedController());
      final service = feedController.service ?? (Get.isRegistered<CommunityService>() ? Get.find<CommunityService>() : Get.put(CommunityService()));
      final results = await service.searchCommunityHashtags(query.replaceAll('#', '').trim(), limit: 20);
      setState(() {
        _searchResults = results;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _toggleHashtag(CommunityHashtag tag) {
    final clean = tag.name.replaceAll('#', '').trim();
    final existsIndex = _selected.indexWhere((h) => h.name.toLowerCase() == clean.toLowerCase());

    if (existsIndex >= 0) {
      setState(() {
        _selected.removeAt(existsIndex);
      });
    } else {
      if (_selected.length >= 10) {
        Get.snackbar(
          'post_hashtags_limit_title'.tr,
          'post_hashtags_limit_message'.tr,
          backgroundColor: Colors.black87,
          colorText: Colors.white,
        );
        return;
      }
      setState(() {
        _selected.add(CommunityHashtag(id: tag.id.isNotEmpty ? tag.id : clean, name: clean, postCount: tag.postCount));
      });
    }
  }

  void _addNewHashtag(String rawQuery) {
    final clean = rawQuery.replaceAll('#', '').trim();
    if (clean.isEmpty) return;

    if (_selected.length >= 10) {
      Get.snackbar(
        'post_hashtags_limit_title'.tr,
        'post_hashtags_limit_message'.tr,
        backgroundColor: Colors.black87,
        colorText: Colors.white,
      );
      return;
    }

    final exists = _selected.any((h) => h.name.toLowerCase() == clean.toLowerCase());
    if (!exists) {
      setState(() {
        _selected.add(CommunityHashtag(id: clean, name: clean, postCount: 0));
        _searchController.clear();
        _searchHashtags('');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        centerTitle: true,
        title: Text('post_hashtags_title'.tr),
        titleTextStyle: AppTextStyles.h5.copyWith(color: colorScheme.onSurface),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton(
              onPressed: () => Get.back(result: _selected),
              child: Text(
                'post_hashtags_save'.trParams({'count': '${_selected.length}'}),
                style: AppTextStyles.buttonSmall.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Search Bar
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'post_hashtags_search_hint'.tr,
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: () => _addNewHashtag(_searchController.text),
                  ),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                ),
                onChanged: _searchHashtags,
                onSubmitted: _addNewHashtag,
              ),
            ),

            // Selected Hashtags (Plain text with X icon, no background box/border)
            if (_selected.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: _selected.map((h) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '#${h.name}',
                        style: TextStyle(color: colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () => setState(() => _selected.removeWhere((item) => item.name.toLowerCase() == h.name.toLowerCase())),
                        child: Icon(Icons.close_rounded, size: 16, color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  )).toList(),
                ),
              ),

            const Divider(height: 20),

            // Results List
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _searchResults.isEmpty
                      ? Center(
                          child: Text('post_hashtags_empty'.tr, style: AppTextStyles.body.copyWith(color: colorScheme.outline)),
                        )
                      : ListView.builder(
                          itemCount: _searchResults.length,
                          itemBuilder: (context, index) {
                            final tag = _searchResults[index];
                            final isSelected = _selected.any((h) => h.name.toLowerCase() == tag.name.toLowerCase());

                            return CheckboxListTile(
                              title: Text('#${tag.name}', style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text('post_hashtags_publications_count'.trParams({'count': '${tag.postCount}'})),
                              value: isSelected,
                              activeColor: AppColors.primary,
                              onChanged: (_) => _toggleHashtag(tag),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
