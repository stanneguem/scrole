import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:scrole/app/theme/app_colors.dart';
import 'package:scrole/app/theme/text_styles.dart';
import 'package:scrole/shared/utils/number_formatter.dart';
import 'package:scrole/shared/widgets/app_cached_image.dart';
import '../../centre/models/event_model.dart';
import '../../centre/repositories/event_repository.dart';

/// Écran complet dédié à la notation d'un événement (Échelle de 1 à 10).
class EventRatingScreen extends StatefulWidget {
  final EventModel event;

  const EventRatingScreen({
    super.key,
    required this.event,
  });

  @override
  State<EventRatingScreen> createState() => _EventRatingScreenState();
}

class _EventRatingScreenState extends State<EventRatingScreen> {
  final EventRepository _repository = Get.find<EventRepository>();

  int? _selectedScore;
  double _ratingAverage = 0.0;
  int _ratingsCount = 0;
  int? _myExistingRating;

  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadRatingStats();
  }

  Future<void> _loadRatingStats() async {
    setState(() => _isLoading = true);

    try {
      final stats = await _repository.getEventInteractionStats(widget.event.id);
      if (stats != null && mounted) {
        final avg = (stats['rating_average'] as num?)?.toDouble() ?? 0.0;
        final count = (stats['ratings_count'] as num?)?.toInt() ?? 0;
        final myScore = (stats['my_rating'] as num?)?.toInt();

        setState(() {
          _ratingAverage = avg;
          _ratingsCount = count;
          _myExistingRating = myScore;
          if (myScore != null && myScore >= 1 && myScore <= 10) {
            _selectedScore = myScore;
          } else {
            _selectedScore = null;
          }
          _isLoading = false;
        });
      } else if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('[EventRatingScreen] _loadRatingStats error: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  bool get _eventHasStarted => !DateTime.now().isBefore(widget.event.startsAt);

  String get _selectedEmoji {
    final score = _selectedScore;
    if (score == null) return '🤔';
    if (score <= 3) return '😡';
    if (score <= 5) return '😕';
    if (score <= 7) return '😐';
    if (score <= 9) return '😊';
    return '🤩';
  }

  void _selectScore(int score) {
    if (!_eventHasStarted || _isSaving) return;
    HapticFeedback.selectionClick();
    setState(() => _selectedScore = score);
  }

  String _friendlyRatingError(Object error) {
    final message = error.toString().toLowerCase();
    if (message.contains('pourrez noter') || message.contains('aura commencé')) {
      return 'event_rating_error_not_started'.tr;
    }
    if (message.contains('équipe de l') || message.contains('team')) {
      return 'event_rating_error_team'.tr;
    }
    if (message.contains('conditions d’accès') || message.contains('conditions d\'accès') || message.contains('accès à cet événement')) {
      return 'event_rating_error_access'.tr;
    }
    if (message.contains('authentification')) {
      return 'event_rating_error_auth'.tr;
    }
    return 'event_rating_error_generic'.tr;
  }

  Future<void> _submitRating() async {
    if (_selectedScore == null || _isSaving) return;
    if (!_eventHasStarted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('event_rating_error_not_started'.tr),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      await _repository.rateEvent(
        eventId: widget.event.id,
        rating: _selectedScore!,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'event_rating_saved'.trParams({'score': _selectedScore.toString()}),
              style: AppTextStyles.bodySmall.copyWith(color: Colors.white),
            ),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
        Get.back(result: true);
      }
    } catch (e) {
      debugPrint('[EventRatingScreen] _submitRating error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _friendlyRatingError(e),
              style: AppTextStyles.bodySmall.copyWith(color: Colors.white),
            ),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Map<String, String> _getSatisfactionInfo(int? score) {
    if (score == null) {
      return {
        'title': 'event_rating_choose'.tr,
        'desc': 'event_rating_description_empty'.tr,
        'color': '0xFF9CA3AF',
      };
    }
    if (score <= 3) {
      return {
        'title': 'event_rating_sentiment_1'.tr,
        'desc': 'event_rating_description_1'.tr,
        'color': '0xFFEF4444',
      };
    } else if (score <= 5) {
      return {
        'title': 'event_rating_sentiment_2'.tr,
        'desc': 'event_rating_description_2'.tr,
        'color': '0xFFF97316',
      };
    } else if (score <= 7) {
      return {
        'title': 'event_rating_sentiment_3'.tr,
        'desc': 'event_rating_description_3'.tr,
        'color': '0xFFEAB308',
      };
    } else if (score <= 9) {
      return {
        'title': 'event_rating_sentiment_4'.tr,
        'desc': 'event_rating_description_4'.tr,
        'color': '0xFF10B981',
      };
    } else {
      return {
        'title': 'event_rating_sentiment_5'.tr,
        'desc': 'event_rating_description_5'.tr,
        'color': '0xFF3B82F6',
      };
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final info = _getSatisfactionInfo(_selectedScore);
    final themeColor = Color(int.parse(info['color']!));

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Get.back(),
        ),
        title: Text(
          'event_rating_title'.tr,
          style: GoogleFonts.spaceGrotesk(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              onPressed: (_selectedScore == null || _isSaving || !_eventHasStarted)
                  ? null
                  : _submitRating,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                disabledForegroundColor: colorScheme.onSurfaceVariant.withValues(alpha: 0.45),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                textStyle: GoogleFonts.spaceGrotesk(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primary,
                      ),
                    )
                  : Text(_myExistingRating != null ? 'event_rating_update'.tr : 'event_rating_submit'.tr),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // En-tête visuel de l'événement
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: SizedBox(
                      width: double.infinity,
                      height: 140,
                      child: widget.event.coverImageUrl != null && widget.event.coverImageUrl!.isNotEmpty
                          ? AppCachedImage(imageUrl: widget.event.coverImageUrl!, fit: BoxFit.cover)
                          : Container(
                              color: colorScheme.surfaceContainerHighest,
                              child: const Icon(Icons.event_rounded, size: 48, color: AppColors.textSecondary),
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.event.name,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),

                  // Statistiques actuelles de notation de l'événement
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.star_rounded, size: 18, color: Color(0xFFEAB308)),
                      const SizedBox(width: 4),
                      Text(
                        _ratingsCount > 0
                            ? '${_ratingAverage.toStringAsFixed(1)} / 10'
                            : 'event_rating_no_ratings'.tr,
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      if (_ratingsCount > 0) ...[
                        const SizedBox(width: 6),
                        Text(
                          '(${NumberFormatter.formatCount(_ratingsCount)} note${_ratingsCount > 1 ? 's' : ''})',
                          style: AppTextStyles.caption.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ],
                  ),
                  if (_myExistingRating != null) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'event_rating_current'.trParams({'score': _myExistingRating.toString()}),
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],

                  if (!_eventHasStarted) ...[
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: colorScheme.tertiaryContainer.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.45)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.schedule_rounded, color: colorScheme.onTertiaryContainer, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'event_rating_waiting'.tr,
                              style: AppTextStyles.bodySmall.copyWith(color: colorScheme.onTertiaryContainer, height: 1.35),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 28),

                  // Affichage de la note sélectionnée
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    decoration: BoxDecoration(
                      color: themeColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: themeColor.withValues(alpha: 0.4), width: 1.5),
                    ),
                    child: Column(
                      children: [
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          transitionBuilder: (child, animation) => ScaleTransition(
                            scale: animation,
                            child: FadeTransition(opacity: animation, child: child),
                          ),
                          child: Text(
                            _selectedEmoji,
                            key: ValueKey(_selectedEmoji),
                            style: const TextStyle(fontSize: 58, height: 1.2),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _selectedScore != null ? '$_selectedScore / 10' : '- / 10',
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                            color: themeColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          info['title']!,
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          info['desc']!,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 28),

                  Text(
                    'event_rating_select_prompt'.tr,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Grille de sélection de 1 à 10
                  Wrap(
                    spacing: 10,
                    runSpacing: 12,
                    alignment: WrapAlignment.center,
                    children: List.generate(10, (index) {
                      final score = index + 1;
                      final isSelected = score == _selectedScore;

                      return InkWell(
                        onTap: _eventHasStarted ? () => _selectScore(score) : null,
                        borderRadius: BorderRadius.circular(14),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: isSelected ? themeColor : colorScheme.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isSelected ? themeColor : colorScheme.outlineVariant.withValues(alpha: 0.4),
                              width: isSelected ? 2 : 1,
                            ),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: themeColor.withValues(alpha: 0.3),
                                      blurRadius: 8,
                                      offset: const Offset(0, 3),
                                    )
                                  ]
                                : [],
                          ),
                          child: Center(
                            child: Text(
                              '$score',
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isSelected ? Colors.white : colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),

                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }
}
