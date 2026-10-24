import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/text_styles.dart';
import '../../centre/models/activity_model.dart';
import '../../externe/repositories/activity_repository.dart';

class ActivityStatsScreen extends StatefulWidget {
  final Activity activity;

  const ActivityStatsScreen({super.key, required this.activity});

  @override
  State<ActivityStatsScreen> createState() => _ActivityStatsScreenState();
}

class _ActivityStatsScreenState extends State<ActivityStatsScreen> {
  final ActivityRepository _repository = ActivityRepository();
  bool _isLoading = true;
  Map<String, dynamic>? _stats;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _isLoading = true);
    try {
      final res = await _repository.getActivityStatsRpc(widget.activity.id);
      if (mounted) {
        setState(() {
          _stats = res;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[ActivityStatsScreen] Error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final addedTotal = _stats?['added_count_total'] ?? widget.activity.addedCount;
    final currentEvents = _stats?['current_events_count'] ?? 0;
    final favorites = _stats?['favorites_count'] ?? 0;
    final ranking = _stats?['classement'] as Map?;
    final rank = ranking?['rang'] ?? '-';
    final total = ranking?['sur'] ?? '-';
    final score = ranking?['score'] ?? '-';

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          'Statistiques',
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Get.back(),
        ),
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : RefreshIndicator(
                color: AppColors.primary,
                onRefresh: _loadStats,
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    // Badge Rang Plateforme
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppColors.primary,
                            AppColors.primary.withValues(alpha: 0.8),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        children: [
                          const Icon(Icons.emoji_events_rounded, color: Colors.amber, size: 40),
                          const SizedBox(height: 10),
                          Text(
                            'CLASSEMENT PLATEFORME',
                            style: AppTextStyles.labelSmall.copyWith(color: Colors.white70, letterSpacing: 1.2),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Rang $rank sur $total',
                            style: GoogleFonts.spaceGrotesk(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Score de popularité : $score',
                            style: AppTextStyles.bodySmall.copyWith(color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    Text('MÉTRIQUES D\'UTILISATION', style: AppTextStyles.labelSmall.copyWith(letterSpacing: 1.2, color: colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 12),

                    _MetricCard(
                      icon: Icons.history_edu_rounded,
                      title: 'Ajouts cumulés aux événements',
                      value: '$addedTotal',
                      color: AppColors.primary,
                    ),
                    const SizedBox(height: 12),

                    _MetricCard(
                      icon: Icons.event_available_rounded,
                      title: 'Événements actuels proposant cette activité',
                      value: '$currentEvents',
                      color: const Color(0xFF3B82F6),
                    ),
                    const SizedBox(height: 12),

                    _MetricCard(
                      icon: Icons.star_rounded,
                      title: 'Ajouts en favoris par les utilisateurs',
                      value: '$favorites',
                      color: Colors.amber[800]!,
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final Color color;

  const _MetricCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(title, style: AppTextStyles.body),
            ),
            Text(
              value,
              style: GoogleFonts.spaceGrotesk(fontSize: 22, fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
      ),
    );
  }
}
