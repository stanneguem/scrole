import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/text_styles.dart';
import '../../../../shared/utils/number_formatter.dart';
import '../../centre/models/event_model.dart';
import '../controllers/event_stats_controller.dart';
import 'event_guest_invitations_screen.dart';
import 'event_sponsors_screen.dart';

class EventStatsDashboardScreen extends StatelessWidget {
  final EventModel? event;

  const EventStatsDashboardScreen({super.key, this.event});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final args = event ?? Get.arguments;
    String eventId = '';
    EventModel? initialEvent;

    if (args is EventModel) {
      initialEvent = args;
      eventId = args.id;
    } else {
      eventId = Get.parameters['id'] ?? '';
    }

    final tag = 'stats_$eventId';
    final controller = Get.put(
      EventStatsController(eventId: eventId),
      tag: tag,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'event_budget_insights_title'.tr,
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'notifications_refresh'.tr,
            onPressed: () => controller.refreshStatistics(),
          ),
        ],
      ),
      body: Obx(() {
        if (controller.isLoading.value && controller.stats.value == null) {
          return const Center(child: CircularProgressIndicator());
        }

        if (controller.errorMessage.value != null && controller.stats.value == null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline_rounded, size: 52, color: AppColors.error),
                  const SizedBox(height: 16),
                  Text(
                    'Impossible de charger les statistiques',
                    style: AppTextStyles.h4,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    controller.errorMessage.value!,
                    style: AppTextStyles.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () => controller.refreshStatistics(),
                    icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                    label: const Text('Réessayer', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                  ),
                ],
              ),
            ),
          );
        }

        final stats = controller.stats.value!;
        final info = stats.event;
        final overview = stats.overview;
        final audience = stats.audience;
        final attendance = stats.attendance;
        final engagement = stats.engagement;
        final funnel = stats.funnel;
        final financial = stats.financial;
        final prestige = stats.prestige;
        final extended = stats.extended;
        final demographics = extended.demographics;
        final calendarDays = extended.calendarDays;
        final simulation = extended.simulation;
        final engagementDetails = extended.engagementDetails;

        return RefreshIndicator(
          onRefresh: () => controller.refreshStatistics(),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (controller.isStale.value) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.amber),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.wifi_off_rounded, size: 18, color: Colors.amber[800]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Données hors-ligne affichées. Balayez vers le bas pour rafraîchir.',
                          style: TextStyle(fontSize: 12, color: Colors.amber[900], fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // En-tête Événement
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.insights_rounded, color: AppColors.primary, size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(info.name, style: AppTextStyles.h4),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: info.isFree
                                      ? AppColors.success.withValues(alpha: 0.15)
                                      : AppColors.primary.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  info.isFree ? 'Événement Gratuit' : 'Événement Payant',
                                  style: AppTextStyles.caption.copyWith(
                                    color: info.isFree ? AppColors.success : AppColors.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: List.generate(
                                  5,
                                  (index) => Icon(
                                    index < prestige.stars ? Icons.star_rounded : Icons.star_outline_rounded,
                                    size: 14,
                                    color: Colors.amber,
                                  ),
                                ),
                              ),
                              Text(
                                '${prestige.stars.toStringAsFixed(1)} (${prestige.score.toStringAsFixed(1)} pts)',
                                style: AppTextStyles.caption.copyWith(
                                  color: Colors.amber[900],
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // KPI PRINCIPAUX / POPULATION
              Container(
                padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.3), width: 1.5),
                ),
                child: Column(
                  children: [
                    Text(
                      NumberFormatter.formatCount(overview.totalUniquePeople),
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 44,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Personnes uniques connectées',
                      style: AppTextStyles.h4.copyWith(fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Divider(color: colors.outlineVariant.withValues(alpha: 0.4)),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _kpiSubItem(colors, 'Agenda', NumberFormatter.formatCount(overview.agendaCount)),
                        _kpiSubItem(colors, 'Présents', NumberFormatter.formatCount(overview.uniqueAttendees)),
                        _kpiSubItem(colors, 'Taux présence', '${overview.attendanceRate.toStringAsFixed(0)}%'),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // FUNNEL DE CONVERSION
              _sectionHeader(colors, Icons.filter_alt_rounded, 'Funnel de Conversion'),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    _funnelStep(colors, 'Sessions Aperçu', NumberFormatter.formatCount(funnel.previewSessions), 1.0, AppColors.primary),
                    _funnelStep(colors, 'Ajouts Agenda', '${NumberFormatter.formatCount(funnel.agendaAdditions)} (${funnel.previewToAgendaRate.toStringAsFixed(0)}%)', (funnel.previewToAgendaRate / 100).clamp(0.05, 1.0), Colors.blue),
                    _funnelStep(colors, 'Participants Présents', '${NumberFormatter.formatCount(funnel.uniqueAttendees)} (${funnel.agendaToAttendanceRate.toStringAsFixed(0)}%)', (funnel.agendaToAttendanceRate / 100).clamp(0.05, 1.0), AppColors.success),
                    _funnelStep(colors, 'Participants Activités', '${NumberFormatter.formatCount(funnel.activityParticipants)} (${funnel.attendanceToActivityRate.toStringAsFixed(0)}%)', (funnel.attendanceToActivityRate / 100).clamp(0.05, 1.0), Colors.amber[800]!),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // ENGAGEMENT ET INTERACTIONS
              _sectionHeader(colors, Icons.thumb_up_alt_rounded, 'Interactions & Engagement'),
              const SizedBox(height: 10),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 1.6,
                children: [
                  _statCard(colors, Icons.favorite_rounded, 'J\'aime', NumberFormatter.formatCount(engagement.likesCount), Colors.pink),
                  _statCard(colors, Icons.calendar_month_rounded, 'Ajouts Agenda', NumberFormatter.formatCount(engagement.calendarCount), AppColors.primary),
                  _statCard(colors, Icons.chat_bubble_rounded, 'Commentaires', NumberFormatter.formatCount(engagement.commentsCount), Colors.blue),
                  _statCard(colors, Icons.share_rounded, 'Personnes ayant partagé', NumberFormatter.formatCount(engagement.uniqueSharersCount), Colors.purple, subtitle: '${NumberFormatter.formatCount(engagement.sharesCount)} partages au total'),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.star_rounded, color: Colors.amber, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Note Moyenne', style: AppTextStyles.labelLarge),
                          Text('${engagement.ratingAverage.toStringAsFixed(1)} / 5.0 (${NumberFormatter.formatCount(engagement.ratingsCount)} avis)', style: AppTextStyles.caption),
                        ],
                      ),
                    ),
                    Text('${prestige.score.toStringAsFixed(1)} pts', style: AppTextStyles.h4.copyWith(color: AppColors.primary)),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // PROFIL DU PUBLIC : données renseignées dans les profils, sans identifier les participants.
              _sectionHeader(colors, Icons.groups_rounded, 'Profil du public'),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: colors.surfaceContainerLow, borderRadius: BorderRadius.circular(16)),
                child: Column(children: [
                  Row(children: [
                    Expanded(child: _statCard(colors, Icons.male, 'Hommes', NumberFormatter.formatCount(_metric(demographics, 'men')), Colors.blue)),
                    const SizedBox(width: 10),
                    Expanded(child: _statCard(colors, Icons.female, 'Femmes', NumberFormatter.formatCount(_metric(demographics, 'women')), Colors.pink)),
                  ]),
                  const SizedBox(height: 12),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text('Âge moyen', style: AppTextStyles.bodySmall),
                    Text(demographics['average_age'] == null ? 'Données insuffisantes' : '${_metricDouble(demographics, 'average_age').toStringAsFixed(1)} ans', style: AppTextStyles.labelLarge),
                  ]),
                  const SizedBox(height: 10),
                  ...[
                    ('Moins de 18 ans', 'age_under_18'), ('18–24 ans', 'age_18_24'), ('25–34 ans', 'age_25_34'),
                    ('35–44 ans', 'age_35_44'), ('45–54 ans', 'age_45_54'), ('55 ans et plus', 'age_55_plus'),
                  ].map((entry) => Padding(
                    padding: const EdgeInsets.only(top: 7),
                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text(entry.$1, style: AppTextStyles.caption),
                      Text(NumberFormatter.formatCount(_metric(demographics, entry.$2)), style: AppTextStyles.labelMedium),
                    ]),
                  )),
                  const SizedBox(height: 8),
                  Text('Profils avec âge renseigné : ${NumberFormatter.formatCount(_metric(demographics, 'age_known'))} · Genre non renseigné : ${NumberFormatter.formatCount(_metric(demographics, 'gender_unknown'))}', style: AppTextStyles.caption),
                ]),
              ),
              const SizedBox(height: 20),

              // JOURS CHOISIS DANS L’AGENDA
              _sectionHeader(colors, Icons.date_range_rounded, 'Jours de participation prévus'),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: colors.surfaceContainerLow, borderRadius: BorderRadius.circular(16)),
                child: Column(children: [
                  _metricRow('Jours sélectionnés au total', _metric(calendarDays, 'selected_days')),
                  _metricRow('Personnes ayant choisi des jours', _metric(calendarDays, 'users_with_days')),
                  _metricRow('Moyenne de jours par personne', _metricDouble(calendarDays, 'average_days_per_person').toStringAsFixed(1)),
                ]),
              ),
              const SizedBox(height: 20),

              // SIMULATIONS DE BUDGET
              _sectionHeader(colors, Icons.calculate_outlined, 'Simulations de budget'),
              const SizedBox(height: 10),
              GridView.count(
                shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 1.55,
                children: [
                  _statCard(colors, Icons.open_in_new_rounded, 'Ouvertures', NumberFormatter.formatCount(_metric(simulation, 'sessions_started')), AppColors.primary),
                  _statCard(colors, Icons.people_alt_outlined, 'event_budget_insights_unique'.tr, NumberFormatter.formatCount(_metric(simulation, 'unique_budget_users')), Colors.blue),
                  _statCard(colors, Icons.check_circle_outline, 'event_budget_insights_confirmed'.tr, NumberFormatter.formatCount(_metric(simulation, 'sessions_confirmed')), AppColors.success),
                  _statCard(colors, Icons.confirmation_number_outlined, 'event_budget_insights_tickets'.tr, NumberFormatter.formatCount(((simulation['ticket_choices'] as List?)?.fold<int>(0, (sum, item) => sum + _metric(Map<String, dynamic>.from(item as Map), 'selection_count')) ?? 0)), Colors.purple),
                  _statCard(colors, Icons.local_activity_outlined, 'event_budget_insights_activities'.tr, NumberFormatter.formatCount(((simulation['activity_choices'] as List?)?.fold<int>(0, (sum, item) => sum + _metric(Map<String, dynamic>.from(item as Map), 'selection_interactions')) ?? 0)), Colors.orange),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: colors.surfaceContainerLow, borderRadius: BorderRadius.circular(16)),
                child: Column(children: [
                  if (simulation['budget_by_currency'] is List && (simulation['budget_by_currency'] as List).isNotEmpty) ...[
                    ...(simulation['budget_by_currency'] as List).whereType<Map>().map((item) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Devise : ${item['currency'] ?? '—'}', style: AppTextStyles.labelLarge),
                        _metricRow('Simulations terminées', _metric(item.cast<String, dynamic>(), 'simulations')),
                        _metricRow('Budget moyen', '${_metricDouble(item.cast<String, dynamic>(), 'average_budget').toStringAsFixed(0)} ${item['currency'] ?? ''}'),
                        _metricRow('Budget cumulé', '${_metricDouble(item.cast<String, dynamic>(), 'total_budget').toStringAsFixed(0)} ${item['currency'] ?? ''}'),
                      ]),
                    )),
                  ] else
                    Text('Les montants simulés apparaîtront ici après les premières simulations terminées.', style: AppTextStyles.caption),
                ]),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: colors.surfaceContainerLow, borderRadius: BorderRadius.circular(16)),
                child: Column(children: [
                  _metricRow('event_budget_insights_rate'.tr,
                    simulation['confirmation_rate'] == null ? '—' : '${_metricDouble(simulation, 'confirmation_rate').toStringAsFixed(1)} %'),
                  _metricRow('event_budget_insights_abandoned'.tr, _metric(simulation, 'unconfirmed_sessions')),
                  _metricRow('event_budget_insights_average'.tr,
                    simulation['average_confirmed_budget'] == null ? '—' : _metricDouble(simulation, 'average_confirmed_budget').toStringAsFixed(0)),
                ]),
              ),
              const SizedBox(height: 12),
              if (simulation['ticket_choices'] is List && (simulation['ticket_choices'] as List).isNotEmpty) ...[
                _sectionHeader(colors, Icons.confirmation_number_outlined, 'event_budget_insights_tickets'.tr),
                const SizedBox(height: 8),
                Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: colors.surfaceContainerLow, borderRadius: BorderRadius.circular(16)), child: Column(children: [
                  ...(simulation['ticket_choices'] as List).whereType<Map>().map((item) => _metricRow('${item['name'] ?? 'Billet'}', _metric(item.cast<String, dynamic>(), 'selection_count'))),
                ])),
                const SizedBox(height: 16),
              ],
              if (simulation['activity_choices'] is List && (simulation['activity_choices'] as List).isNotEmpty) ...[
                _sectionHeader(colors, Icons.local_activity_outlined, 'event_budget_insights_activities'.tr),
                const SizedBox(height: 8),
                Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: colors.surfaceContainerLow, borderRadius: BorderRadius.circular(16)), child: Column(children: [
                  ...(simulation['activity_choices'] as List).whereType<Map>().map((item) => _metricRow('${item['name'] ?? 'Activité'}', _metric(item.cast<String, dynamic>(), 'selection_interactions'))),
                ])),
                const SizedBox(height: 16),
              ],

              // DÉTAIL DES INTERACTIONS
              _sectionHeader(colors, Icons.touch_app_rounded, 'Détail des interactions'),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: colors.surfaceContainerLow, borderRadius: BorderRadius.circular(16)),
                child: Column(children: [
                  _metricRow('Ouvertures de la fiche', _metric(engagementDetails, 'detail_views')),
                  _metricRow('Commentaires', _metric(engagementDetails, 'comments')),
                  _metricRow('Réponses aux commentaires', _metric(engagementDetails, 'replies')),
                  _metricRow('J’aime sur les commentaires', _metric(engagementDetails, 'comment_likes')),
                ]),
              ),
              const SizedBox(height: 20),

              // COMPLÉTUDE DES DONNÉES EXISTANTES
              _sectionHeader(colors, Icons.fact_check_outlined, 'Audience & présence détaillées'),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: colors.surfaceContainerLow, borderRadius: BorderRadius.circular(16)),
                child: Column(children: [
                  _metricRow('Personnes dans l’agenda', audience.calendarPeopleCount),
                  _metricRow('Participants réguliers', audience.regularAttendeesCount),
                  _metricRow('Invités d’honneur', audience.guestsOfHonorCount),
                  _metricRow('Sponsors', audience.sponsorsCount),
                  _metricRow('Staff', audience.staffCount),
                  _metricRow('Co-organisateurs', audience.cofoundersCount),
                  _metricRow('Fondateur', audience.founderCount),
                  const Divider(height: 20),
                  _metricRow('Scans valides', attendance.totalValidCheckins),
                  _metricRow('Scans invalidés', attendance.invalidatedCheckins),
                  _metricRow('Participants aux activités', attendance.activityParticipants),
                  _metricRow('Taux de non-présentation', '${attendance.noShowRate.toStringAsFixed(1)} %'),
                ]),
              ),
              const SizedBox(height: 20),

              _sectionHeader(colors, Icons.travel_explore_rounded, 'Découverte & intérêt'),
              const SizedBox(height: 10),
              GridView.count(
                shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 1.55,
                children: [
                  _statCard(colors, Icons.visibility_outlined, 'Sessions aperçu', NumberFormatter.formatCount(stats.discovery.previewSessions), AppColors.primary),
                  _statCard(colors, Icons.person_search_outlined, 'Visiteurs uniques', NumberFormatter.formatCount(stats.discovery.uniquePreviewUsers), Colors.blue),
                  _statCard(colors, Icons.confirmation_number_outlined, 'Billets simulés', NumberFormatter.formatCount(stats.discovery.ticketSelectionsCount), Colors.purple),
                  _statCard(colors, Icons.local_activity_outlined, 'Activités simulées', NumberFormatter.formatCount(stats.discovery.activitySelectionsCount), Colors.orange),
                ],
              ),
              const SizedBox(height: 20),

              _sectionHeader(colors, Icons.stacked_bar_chart_rounded, 'Participation aux activités'),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: colors.surfaceContainerLow, borderRadius: BorderRadius.circular(16)),
                child: Column(children: [
                  _metricRow('Aucune activité', stats.activityDepth.attendeesWith0Activities),
                  _metricRow('Une activité', stats.activityDepth.attendeesWith1Activity),
                  _metricRow('Deux activités', stats.activityDepth.attendeesWith2Activities),
                  _metricRow('Trois activités ou plus', stats.activityDepth.attendeesWith3PlusActivities),
                  _metricRow('Moyenne d’activités par participant', stats.activityDepth.averageActivitiesPerAttendee.toStringAsFixed(1)),
                ]),
              ),
              const SizedBox(height: 20),

              _sectionHeader(colors, Icons.badge_outlined, 'Performance du staff'),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: colors.surfaceContainerLow, borderRadius: BorderRadius.circular(16)),
                child: Column(children: [
                  _metricRow('Membres du staff', stats.staff.totalStaff),
                  _metricRow('Staff ayant effectué des scans', stats.staff.staffMembersWithScans),
                  _metricRow('Scans validés par le staff', stats.staff.totalStaffScans),
                  _metricRow('Moyenne de scans par membre actif', stats.staff.averageScansPerActiveStaff.toStringAsFixed(1)),
                ]),
              ),
              const SizedBox(height: 20),

              _sectionHeader(colors, Icons.mail_outline_rounded, 'Suivi des invitations'),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: colors.surfaceContainerLow, borderRadius: BorderRadius.circular(16)),
                child: Column(children: [
                  Text('Invitations d’honneur', style: AppTextStyles.labelLarge),
                  _metricRow('Envoyées', stats.invitations.guestInvitations.sent),
                  _metricRow('Acceptées', stats.invitations.guestInvitations.accepted),
                  _metricRow('Refusées', stats.invitations.guestInvitations.declined),
                  _metricRow('En attente', stats.invitations.guestInvitations.pending),
                  _metricRow('Taux d’acceptation', '${stats.invitations.guestInvitations.acceptanceRate.toStringAsFixed(1)} %'),
                  const Divider(height: 20),
                  Text('Invitations sponsors', style: AppTextStyles.labelLarge),
                  _metricRow('Envoyées', stats.invitations.sponsorInvitations.sent),
                  _metricRow('Acceptées', stats.invitations.sponsorInvitations.accepted),
                  _metricRow('Refusées', stats.invitations.sponsorInvitations.declined),
                  _metricRow('En attente', stats.invitations.sponsorInvitations.pending),
                  _metricRow('Taux d’acceptation', '${stats.invitations.sponsorInvitations.acceptanceRate.toStringAsFixed(1)} %'),
                ]),
              ),
              const SizedBox(height: 20),

              // BILLETS ET ACTIVITÉS
              if (stats.activities.isNotEmpty) ...[
                _sectionHeader(colors, Icons.local_activity_rounded, 'Activités Événement'),
                const SizedBox(height: 10),
                ...stats.activities.map((act) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Text('#${act.rankByParticipation}', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(act.name, style: AppTextStyles.labelLarge),
                            Text('${NumberFormatter.formatCount(act.participationCount)} participations (${NumberFormatter.formatCount(act.uniqueParticipants)} uniques) · ${NumberFormatter.formatPrice(act.price, act.currencyCode)}', style: AppTextStyles.caption),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(NumberFormatter.formatPrice(act.estimatedGrossRevenue, act.currencyCode), style: AppTextStyles.labelMedium.copyWith(color: AppColors.success)),
                    ],
                  ),
                )),
                const SizedBox(height: 20),
              ],

              // INFOS FINANCIÈRES ESTIMÉES
              _sectionHeader(colors, Icons.account_balance_wallet_rounded, 'Finances (Estimations)'),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: Text('Revenu Réel', style: AppTextStyles.bodySmall)),
                        Text(
                          financial.isRealRevenueAvailable ? NumberFormatter.formatPrice(financial.estimatedTicketingRevenue, financial.currency) : 'Non suivi actuellement',
                          style: AppTextStyles.caption.copyWith(
                            fontStyle: FontStyle.italic,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: Text('Valeur potentielle billetterie (Agenda)', style: AppTextStyles.bodySmall)),
                        const SizedBox(width: 8),
                        Text(NumberFormatter.formatPrice(financial.estimatedTicketingRevenue, financial.currency), style: AppTextStyles.labelLarge),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: Text('Valeur estimée activités', style: AppTextStyles.bodySmall)),
                        const SizedBox(width: 8),
                        Text(NumberFormatter.formatPrice(financial.estimatedActivityRevenue, financial.currency), style: AppTextStyles.labelLarge.copyWith(color: AppColors.success)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Note : Les montants affichés sont des estimations basées sur la billetterie et la participation aux activités.',
                        style: AppTextStyles.caption,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Raccourcis invitations & sponsors
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Get.to(() => EventGuestInvitationsScreen(
                        event: initialEvent ?? EventModel(id: info.id, creatorId: '', name: info.name, slug: '', startsAt: info.startsAt, createdAt: info.createdAt),
                      )),
                      icon: const Icon(Icons.card_membership_rounded),
                      label: Text('Invités (${NumberFormatter.formatCount(audience.guestsOfHonorCount)})'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Get.to(() => EventSponsorsScreen(
                        event: initialEvent ?? EventModel(id: info.id, creatorId: '', name: info.name, slug: '', startsAt: info.startsAt, createdAt: info.createdAt),
                      )),
                      icon: const Icon(Icons.handshake_rounded),
                      label: Text('Sponsors (${NumberFormatter.formatCount(audience.sponsorsCount)})'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      }),
    );
  }

  int _metric(Map<String, dynamic> values, String key) => int.tryParse('${values[key] ?? 0}') ?? 0;

  double _metricDouble(Map<String, dynamic> values, String key) => double.tryParse('${values[key] ?? 0}') ?? 0;

  Widget _metricRow(String label, Object value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Expanded(child: Text(label, style: AppTextStyles.bodySmall)),
      const SizedBox(width: 12),
      Text('$value', style: AppTextStyles.labelLarge),
    ]),
  );

  Widget _sectionHeader(ColorScheme colors, IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.primary),
        const SizedBox(width: 8),
        Text(title, style: AppTextStyles.h4.copyWith(color: colors.onSurface)),
      ],
    );
  }

  Widget _kpiSubItem(ColorScheme colors, String label, String value) {
    return Column(
      children: [
        Text(value, style: AppTextStyles.h4.copyWith(color: colors.onSurface, fontWeight: FontWeight.bold)),
        Text(label, style: AppTextStyles.caption),
      ],
    );
  }

  Widget _statCard(ColorScheme colors, IconData icon, String label, String value, Color iconColor, {String? subtitle}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(width: 6),
              Expanded(child: Text(label, style: AppTextStyles.caption, overflow: TextOverflow.ellipsis)),
            ],
          ),
          const SizedBox(height: 6),
          Text(value, style: AppTextStyles.h3.copyWith(color: colors.onSurface)),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle, style: AppTextStyles.caption.copyWith(fontSize: 10, color: colors.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }

  Widget _funnelStep(ColorScheme colors, String label, String valStr, double ratio, Color barColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text(label, style: AppTextStyles.bodySmall, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 8),
              Text(valStr, style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              backgroundColor: colors.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
            ),
          ),
        ],
      ),
    );
  }
}
