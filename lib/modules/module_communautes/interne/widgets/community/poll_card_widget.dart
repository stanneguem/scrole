import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PollCardWidget extends StatefulWidget {
  final dynamic poll;
  final String postId;
  final dynamic controller;
  const PollCardWidget({super.key, required this.poll, required this.postId, required this.controller});
  @override
  State<PollCardWidget> createState() => _PollCardWidgetState();
}

class _PollCardWidgetState extends State<PollCardWidget> {
  late Map<String, dynamic> _poll;
  final Set<String> _selected = {};
  bool _saving = false;

  @override
  void initState() { super.initState(); _poll = _map(widget.poll); _sync(); }

  @override
  void didUpdateWidget(covariant PollCardWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.poll != widget.poll) { _poll = _map(widget.poll); _sync(); }
  }

  Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  List<Map<String, dynamic>> get _options {
    final raw = _poll['options'];
    return raw is List ? raw.whereType<Map>().map((v) => Map<String, dynamic>.from(v)).toList() : [];
  }
  String get _kind => (_poll['kind'] ?? 'single').toString();
  bool get _multiple => _kind == 'multiple' || _poll['allow_multiple'] == true;
  bool get _quiz => _kind == 'quiz';
  bool get _closed => _poll['is_closed'] == true;
  bool get _voted => _poll['has_voted'] == true;
  bool get _results => _poll['results_visible'] == true || _closed;
  bool get _canVote => !_closed && !_voted && !_saving;

  void _sync() {
    _selected
      ..clear()
      ..addAll((_poll['my_option_ids'] is List ? _poll['my_option_ids'] as List : const []).map((e) => e.toString()));
    for (final option in _options) {
      if (option['is_mine'] == true && option['id'] != null) _selected.add(option['id'].toString());
    }
  }

  Future<void> _vote() async {
    if (!_canVote) return;
    if (_selected.isEmpty) {
      Get.snackbar('poll_vote_choose_answer'.tr, 'poll_vote_select_option'.tr);
      return;
    }
    setState(() => _saving = true);
    try {
      final response = await Supabase.instance.client.rpc('vote_community_poll', params: {
        'p_post_id': widget.postId,
        'p_option_ids': _selected.toList(),
      });
      if (response is Map && mounted) {
        setState(() { _poll = Map<String, dynamic>.from(response); _sync(); });
      }
    } catch (error) {
      Get.snackbar('poll_vote_failed_title'.tr, 'poll_vote_failed_message'.tr);
      debugPrint('[PollCardWidget] vote error: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _kindLabel() {
    switch (_kind) {
      case 'multiple': return 'poll_kind_multiple'.tr;
      case 'quiz': return 'poll_kind_quiz'.tr;
      case 'this_or_that': return 'poll_kind_this_or_that'.tr;
      default: return 'poll_kind_single_short'.tr;
    }
  }

  String _endLabel() {
    final raw = _poll['ends_at'];
    if (raw == null || raw.toString().isEmpty) return _quiz ? 'poll_kind_quiz'.tr : 'poll_play_now'.tr;
    final end = DateTime.tryParse(raw.toString())?.toLocal();
    if (end == null) return 'poll_play_now'.tr;
    final d = end.difference(DateTime.now());
    if (d.isNegative) return 'poll_ended'.tr;
    if (d.inDays > 0) return 'poll_ends_in_days'.trParams({'count': '${d.inDays}'});
    if (d.inHours > 0) return 'poll_ends_in_hours'.trParams({'count': '${d.inHours}'});
    return 'poll_ends_in_minutes'.trParams({'count': '${d.inMinutes.clamp(1, 59)}'});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final options = _options;
    if (options.isEmpty) return const SizedBox.shrink();

    final voters = (_poll['voters_count'] as num?)?.toInt() ?? 0;
    final correctId = _poll['correct_option_id']?.toString();
    final explanation = (_poll['explanation'] ?? '').toString().trim();
    final question = (_poll['question'] ?? '').toString().trim();
    final imageUrl = (_poll['image_url'] ?? '').toString().trim();
    final accent = _quiz ? colors.tertiary : colors.primary;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: .55)),
        boxShadow: [
          BoxShadow(
            color: colors.shadow.withValues(alpha: theme.brightness == Brightness.dark ? .12 : .045),
            blurRadius: 22,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [accent.withValues(alpha: .19), accent.withValues(alpha: .07)],
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    _quiz ? Icons.lightbulb_rounded : _kind == 'this_or_that' ? Icons.compare_arrows_rounded : Icons.poll_rounded,
                    color: accent,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _kindLabel(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: colors.onSurface,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(_closed ? Icons.lock_clock_rounded : Icons.schedule_rounded, size: 13, color: colors.onSurfaceVariant),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              _closed ? 'poll_interaction_ended'.tr : _endLabel(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest.withValues(alpha: .8),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.people_alt_outlined, size: 14, color: colors.onSurfaceVariant),
                      const SizedBox(width: 5),
                      Text(
                        '$voters',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colors.onSurface,
                          fontWeight: FontWeight.w800,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (question.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
              child: Text(
                question,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontSize: 18,
                  height: 1.3,
                  letterSpacing: -.35,
                  fontWeight: FontWeight.w800,
                  color: colors.onSurface,
                ),
              ),
            ),
          if (imageUrl.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Image.network(imageUrl, width: double.infinity, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
            child: Column(
              children: [
                for (var index = 0; index < options.length; index++)
                  Builder(builder: (context) {
                    final option = options[index];
                    final id = option['id']?.toString() ?? '';
                    final label = (option['label'] ?? option['text'] ?? '').toString();
                    final selected = _selected.contains(id) || option['is_mine'] == true;
                    final correct = _quiz && correctId != null && correctId == id;
                    final percent = (option['percent'] as num?)?.toDouble() ?? 0;
                    final showResult = _results && option['percent'] != null;
                    final votes = (option['votes'] as num?)?.toInt() ?? 0;
                    final optionImage = (option['image_url'] ?? '').toString().trim();
                    final resultColor = correct ? Colors.green : accent;

                    return Padding(
                      padding: EdgeInsets.only(bottom: index == options.length - 1 ? 0 : 10),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _canVote && id.isNotEmpty ? () => setState(() {
                            if (_multiple) {
                              if (!_selected.add(id)) _selected.remove(id);
                            } else {
                              _selected..clear()..add(id);
                            }
                          }) : null,
                          borderRadius: BorderRadius.circular(16),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutCubic,
                            decoration: BoxDecoration(
                              color: selected ? accent.withValues(alpha: .055) : colors.surfaceContainerLow.withValues(alpha: .72),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: correct ? Colors.green.withValues(alpha: .75)
                                    : selected ? accent.withValues(alpha: .8)
                                    : colors.outlineVariant.withValues(alpha: .55),
                                width: selected || correct ? 1.4 : 1,
                              ),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(15),
                              child: Stack(
                                children: [
                                  if (showResult)
                                    Positioned.fill(
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: FractionallySizedBox(
                                          widthFactor: (percent / 100).clamp(0.0, 1.0),
                                          child: DecoratedBox(
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(colors: [
                                                resultColor.withValues(alpha: .17),
                                                resultColor.withValues(alpha: .07),
                                              ]),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          width: 30,
                                          height: 30,
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            color: correct ? Colors.green.withValues(alpha: .13)
                                                : selected ? accent.withValues(alpha: .13)
                                                : colors.surfaceContainerHighest,
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: showResult && correct
                                              ? const Icon(Icons.check_rounded, color: Colors.green, size: 18)
                                              : Icon(
                                                  selected ? (_multiple ? Icons.check_rounded : Icons.radio_button_checked_rounded)
                                                      : (_multiple ? Icons.check_box_outline_blank_rounded : Icons.radio_button_off_rounded),
                                                  color: selected ? accent : colors.outline,
                                                  size: 18,
                                                ),
                                        ),
                                        const SizedBox(width: 11),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(label, style: theme.textTheme.bodyMedium?.copyWith(
                                                color: colors.onSurface,
                                                height: 1.3,
                                                fontWeight: selected || correct ? FontWeight.w700 : FontWeight.w600,
                                              )),
                                              if (optionImage.isNotEmpty) ...[
                                                const SizedBox(height: 10),
                                                ClipRRect(
                                                  borderRadius: BorderRadius.circular(11),
                                                  child: Image.network(optionImage, width: double.infinity, height: 118,
                                                    fit: BoxFit.cover,
                                                    errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                                                ),
                                              ],
                                              if (showResult) ...[
                                                const SizedBox(height: 7),
                                                Text(
                                                  'poll_votes_count'.trParams({'count': '$votes'}),
                                                  style: theme.textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        if (showResult) ...[
                                          const SizedBox(width: 8),
                                          Text(
                                            percent.round().toString() + '%',
                                            style: theme.textTheme.titleSmall?.copyWith(
                                              color: correct ? Colors.green : colors.onSurface,
                                              fontWeight: FontWeight.w900,
                                              fontFeatures: const [FontFeature.tabularFigures()],
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
              ],
            ),
          ),
          if (_quiz && _results && explanation.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: colors.tertiaryContainer.withValues(alpha: .48),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: colors.tertiary.withValues(alpha: .16)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.auto_awesome_rounded, size: 18, color: colors.onTertiaryContainer),
                    const SizedBox(width: 9),
                    Expanded(child: Text(explanation, style: theme.textTheme.bodySmall?.copyWith(
                      height: 1.45, color: colors.onTertiaryContainer))),
                  ],
                ),
              ),
            ),
          if (!_closed && !_voted)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _vote,
                  icon: _saving
                      ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(_quiz ? Icons.check_rounded : Icons.how_to_vote_rounded, size: 18),
                  label: Text(_quiz ? 'poll_submit_answer'.tr : 'poll_vote'.tr),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(49),
                    elevation: 0,
                    backgroundColor: accent,
                    foregroundColor: colors.onPrimary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: -.1),
                  ),
                ),
              ),
            )
          else if (_voted)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 13, 16, 16),
              child: Row(children: [
                Icon(Icons.check_circle_rounded, size: 17, color: colors.primary),
                const SizedBox(width: 7),
                Expanded(child: Text('poll_vote_recorded'.tr, style: theme.textTheme.labelMedium?.copyWith(
                  color: colors.onSurfaceVariant, fontWeight: FontWeight.w600))),
              ]),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 13, 16, 16),
              child: Row(children: [
                Icon(Icons.lock_outline_rounded, size: 16, color: colors.onSurfaceVariant),
                const SizedBox(width: 7),
                Text('poll_interaction_ended'.tr, style: theme.textTheme.labelMedium?.copyWith(
                  color: colors.onSurfaceVariant, fontWeight: FontWeight.w600)),
              ]),
            ),
        ],
      ),
    );
  }
}
