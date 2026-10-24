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
      Get.snackbar('Choisis une réponse', 'Sélectionne au moins une option avant de voter.');
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
      Get.snackbar('Vote non envoyé', 'Impossible d’enregistrer ta réponse. Réessaie.');
      debugPrint('[PollCardWidget] vote error: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _kindLabel() {
    switch (_kind) {
      case 'multiple': return 'Choix multiples';
      case 'quiz': return 'Quiz';
      case 'this_or_that': return 'Tu préfères…';
      default: return 'Sondage';
    }
  }

  String _endLabel() {
    final raw = _poll['ends_at'];
    if (raw == null || raw.toString().isEmpty) return _quiz ? 'Quiz' : 'À toi de jouer';
    final end = DateTime.tryParse(raw.toString())?.toLocal();
    if (end == null) return 'À toi de jouer';
    final d = end.difference(DateTime.now());
    if (d.isNegative) return 'Terminé';
    if (d.inDays > 0) return 'Se termine dans ${d.inDays} j';
    if (d.inHours > 0) return 'Se termine dans ${d.inHours} h';
    return 'Se termine dans ${d.inMinutes.clamp(1, 59)} min';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final options = _options;
    if (options.isEmpty) return const SizedBox.shrink();
    final voters = (_poll['voters_count'] as num?)?.toInt() ?? 0;
    final correctId = _poll['correct_option_id']?.toString();
    final explanation = (_poll['explanation'] ?? '').toString().trim();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: .48)),
        boxShadow: [BoxShadow(color: colors.shadow.withValues(alpha: Theme.of(context).brightness == Brightness.dark ? .08 : .045), blurRadius: 24, offset: const Offset(0, 8))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 46, height: 46,
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: _quiz ? [colors.tertiary.withValues(alpha: .18), colors.primary.withValues(alpha: .09)] : [colors.primary.withValues(alpha: .16), colors.secondary.withValues(alpha: .08)]),
              borderRadius: BorderRadius.circular(16)),
            child: Icon(_quiz ? Icons.lightbulb_rounded : _kind == 'this_or_that' ? Icons.compare_arrows_rounded : Icons.poll_rounded, color: _quiz ? colors.tertiary : colors.primary, size: 24)),
          const SizedBox(width: 11),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_kindLabel(), style: TextStyle(fontSize: 15, letterSpacing: -.2, fontWeight: FontWeight.w800, color: colors.onSurface)),
            const SizedBox(height: 4),
            Row(children: [Icon(_closed ? Icons.lock_clock_rounded : Icons.schedule_rounded, size: 13, color: colors.onSurfaceVariant), const SizedBox(width: 4), Flexible(child: Text(_closed ? 'Interaction terminée' : _endLabel(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: colors.onSurfaceVariant)))]),
          ])),
          if (voters > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: colors.surfaceContainerHighest.withValues(alpha: .75), borderRadius: BorderRadius.circular(30)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.people_alt_outlined, size: 13, color: colors.onSurfaceVariant), const SizedBox(width: 5), Text('$voters vote${voters > 1 ? 's' : ''}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: colors.onSurfaceVariant))])),
        ]),
        const SizedBox(height: 15),
        ...options.map((option) {
          final id = option['id']?.toString() ?? '';
          final label = (option['label'] ?? option['text'] ?? '').toString();
          final selected = _selected.contains(id) || option['is_mine'] == true;
          final correct = _quiz && correctId != null && correctId == id;
          final percent = (option['percent'] as num?)?.toDouble() ?? 0;
          final showResult = _results && option['percent'] != null;
          final votes = (option['votes'] as num?)?.toInt() ?? 0;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
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
                borderRadius: BorderRadius.circular(15),
                child: Container(
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: selected ? colors.primary.withValues(alpha: .08) : colors.surface,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: correct ? Colors.green : selected ? colors.primary : colors.outlineVariant, width: selected || correct ? 1.5 : 1)),
                  child: Stack(children: [
                    if (showResult)
                      Positioned.fill(child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Align(alignment: Alignment.centerLeft, child: FractionallySizedBox(
                          widthFactor: (percent / 100).clamp(0.0, 1.0),
                          child: Container(color: (correct ? Colors.green : colors.primary).withValues(alpha: .12)))))),
                    Row(children: [
                      Icon(correct && showResult ? Icons.check_circle_rounded : selected
                        ? (_multiple ? Icons.check_box_rounded : Icons.radio_button_checked_rounded)
                        : (_multiple ? Icons.check_box_outline_blank_rounded : Icons.radio_button_off_rounded),
                        size: 21, color: correct ? Colors.green : selected ? colors.primary : colors.outline),
                      const SizedBox(width: 10),
                      Expanded(child: Text(label, style: TextStyle(fontSize: 14, height: 1.35, letterSpacing: -.1, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: colors.onSurface))),
                      if (showResult) ...[
                        const SizedBox(width: 8),
                        Text('${percent.round()}%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: colors.onSurface)),
                        if (voters > 0) Text(' ($votes)', style: TextStyle(fontSize: 10, color: colors.onSurfaceVariant)),
                      ],
                    ]),
                  ]),
                ),
              ),
            ),
          );
        }),
        if (_quiz && _results && explanation.isNotEmpty) ...[
          const SizedBox(height: 4),
          Container(
            width: double.infinity, padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: colors.tertiaryContainer.withValues(alpha: .45), borderRadius: BorderRadius.circular(14)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.info_outline_rounded, size: 18, color: colors.onTertiaryContainer),
              const SizedBox(width: 8),
              Expanded(child: Text(explanation, style: TextStyle(fontSize: 12, height: 1.4, color: colors.onTertiaryContainer))),
            ])),
        ],
        if (!_closed && !_voted) ...[
          const SizedBox(height: 4),
          SizedBox(width: double.infinity, child: FilledButton(
            onPressed: _saving ? null : _vote,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50), elevation: 0, shape: const StadiumBorder(), textStyle: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: -.1)),
            child: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(_quiz ? 'Valider ma réponse' : 'Voter'))),
        ],
        if (_voted && !_closed)
          Padding(padding: const EdgeInsets.only(top: 6), child: Row(children: [
            Icon(Icons.check_circle_rounded, size: 16, color: colors.primary),
            const SizedBox(width: 6),
            Text('Ta réponse a été enregistrée', style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
          ])),
      ]),
    );
  }
}
