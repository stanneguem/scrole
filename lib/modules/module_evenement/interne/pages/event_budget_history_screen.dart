import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../app/routes/app_pages.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/text_styles.dart';
import '../../../../shared/utils/number_formatter.dart';
import '../../centre/repositories/event_repository.dart';

class EventBudgetHistoryScreen extends StatefulWidget {
  const EventBudgetHistoryScreen({super.key});
  @override
  State<EventBudgetHistoryScreen> createState() => _EventBudgetHistoryScreenState();
}

class _EventBudgetHistoryScreenState extends State<EventBudgetHistoryScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _sessions = [];
  String? _reusingSessionId;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final raw = await Supabase.instance.client.rpc('get_my_event_budget_sessions', params: {'p_limit': 100});
      final rows = raw is List ? raw : <dynamic>[];
      if (!mounted) return;
      setState(() {
        _sessions = rows.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text('event_budget_history_title'.tr, style: AppTextStyles.h4)),
      body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(
              mainAxisSize: MainAxisSize.min, children: [
                Text('event_budget_history_error'.tr, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                TextButton(onPressed: _load, child: Text('event_budget_history_retry'.tr)),
              ])))
          : _sessions.isEmpty
            ? Center(child: Padding(padding: const EdgeInsets.all(28), child: Text(
                'event_budget_history_empty'.tr, textAlign: TextAlign.center,
                style: TextStyle(color: colors.onSurfaceVariant))))
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView.separated(
                  padding: const EdgeInsets.all(16), itemCount: _sessions.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) => _sessionCard(_sessions[index], colors),
                )),
    );
  }

  Future<void> _reuseSession(Map<String, dynamic> item) async {
    final sessionId = (item['session_id'] ?? '').toString();
    final eventId = (item['event_id'] ?? '').toString();
    if (eventId.isEmpty || _reusingSessionId != null) return;
    setState(() => _reusingSessionId = sessionId);
    try {
      final preview = await Get.find<EventRepository>().getEventPreview(eventId);
      final activities = item['activities'] is List ? item['activities'] as List : <dynamic>[];
      if (!mounted) return;
      await Get.toNamed(
        AppPages.eventBudget.replaceFirst(':id', eventId),
        arguments: {
          'eventId': eventId,
          'tickets': preview.tickets,
          'activities': preview.activitiesLiees,
          'cheapestTicket': preview.cheapestTicket,
          'selectedTicketId': item['ticket_id']?.toString(),
          'selectedActivityIds': activities.whereType<Map>()
              .map((activity) => activity['activity_id']?.toString() ?? '')
              .where((id) => id.isNotEmpty).toList(),
        },
      );
    } catch (e) {
      if (mounted) Get.snackbar('Erreur', 'Impossible de réutiliser ce budget. Vérifiez que l’événement est toujours accessible.');
    } finally {
      if (mounted) setState(() => _reusingSessionId = null);
    }
  }

  Widget _sessionCard(Map<String, dynamic> item, ColorScheme colors) {
    final activities = item['activities'] is List
      ? (item['activities'] as List).whereType<Map>().toList() : <Map>[];
    final saved = DateTime.tryParse('${item['saved_at'] ?? ''}')?.toLocal();
    final amount = (item['viewer_total'] as num?)?.toDouble() ?? 0;
    final currency = (item['currency'] ?? '').toString();
    final eventId = (item['event_id'] ?? '').toString();
    return Material(
      color: colors.surfaceContainerLow, borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: eventId.isEmpty ? null : () => Get.toNamed(AppPages.eventPreviewPath(eventId)),
        child: Padding(padding: const EdgeInsets.all(16), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text((item['event_name'] ?? '—').toString(), style: AppTextStyles.h4),
            if (saved != null) ...[
              const SizedBox(height: 4),
              Text('${'event_budget_history_saved'.tr} ${DateFormat.yMMMd(Get.locale?.toLanguageTag()).add_Hm().format(saved)}',
                style: AppTextStyles.caption.copyWith(color: colors.onSurfaceVariant)),
            ],
            const Divider(height: 22),
            if ((item['ticket_name'] ?? '').toString().isNotEmpty) ...[
              _line('${'event_budget_history_ticket'.tr}:', item['ticket_name'].toString(), colors),
              const SizedBox(height: 4),
              _line('', NumberFormatter.formatPrice(
                (item['ticket_viewer_price'] as num?)?.toDouble() ?? 0,
                (item['ticket_viewer_currency'] ?? currency).toString(),
              ), colors),
            ],
            const SizedBox(height: 6),
            Text('event_budget_history_activities'.tr, style: AppTextStyles.labelLarge),
            if (activities.isEmpty)
              Padding(padding: const EdgeInsets.only(top: 4), child: Text('—', style: AppTextStyles.caption))
            else
              ...activities.map((activity) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: _line((activity['name'] ?? '').toString(),
                  NumberFormatter.formatPrice((activity['price'] as num?)?.toDouble() ?? 0,
                    (activity['currency'] ?? currency).toString()), colors),
              )),
            const Divider(height: 22),
            _line('event_budget_history_total'.tr, NumberFormatter.formatPrice(amount, currency), colors, emphasize: true),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              TextButton(onPressed: eventId.isEmpty ? null : () => Get.toNamed(AppPages.eventPreviewPath(eventId)),
                child: Text('event_budget_history_open_event'.tr)),
              TextButton.icon(
                onPressed: _reusingSessionId == null ? () => _reuseSession(item) : null,
                icon: _reusingSessionId == (item['session_id'] ?? '').toString()
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.replay_rounded, size: 16),
                label: Text('event_budget_history_reuse'.tr),
              ),
            ]),
          ])),
      ),
    );
  }

  Widget _line(String label, String value, ColorScheme colors, {bool emphasize = false}) => Row(children: [
    Expanded(child: Text(label, style: emphasize ? AppTextStyles.labelLarge : AppTextStyles.bodySmall)),
    const SizedBox(width: 10),
    Flexible(child: Text(value, textAlign: TextAlign.end,
      style: emphasize ? AppTextStyles.h4.copyWith(color: AppColors.primary)
        : AppTextStyles.bodySmall.copyWith(color: colors.onSurfaceVariant))),
  ]);
}
