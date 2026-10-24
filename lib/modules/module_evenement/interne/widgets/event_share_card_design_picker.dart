import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:scrole/modules/module_evenement/centre/models/event_preview_model.dart';

class EventShareCardDesign {
  final String name;
  final Color background;
  final Color accent;
  final bool imageFirst;
  final bool minimal;

  const EventShareCardDesign({
    required this.name,
    required this.background,
    required this.accent,
    this.imageFirst = true,
    this.minimal = false,
  });
}

const eventShareCardDesigns = <EventShareCardDesign>[
  EventShareCardDesign(name: 'Nuit élégante', background: Color(0xFF10172A), accent: Color(0xFF8B9CFF)),
  EventShareCardDesign(name: 'Soleil', background: Color(0xFFFFE8C2), accent: Color(0xFFB94C27), imageFirst: false),
  EventShareCardDesign(name: 'Émeraude', background: Color(0xFF073B35), accent: Color(0xFF76E0B5)),
  EventShareCardDesign(name: 'Lavande', background: Color(0xFFEDE7FF), accent: Color(0xFF6941C6), imageFirst: false),
  EventShareCardDesign(name: 'Corail', background: Color(0xFF7D243B), accent: Color(0xFFFFB6A6)),
  EventShareCardDesign(name: 'Minimal', background: Color(0xFFF8FAFC), accent: Color(0xFF111827), minimal: true),
  EventShareCardDesign(name: 'Océan', background: Color(0xFF082F49), accent: Color(0xFF67E8F9), imageFirst: false),
  EventShareCardDesign(name: 'Rose', background: Color(0xFF4A1942), accent: Color(0xFFF9A8D4)),
  EventShareCardDesign(name: 'Citron', background: Color(0xFFF3F6C8), accent: Color(0xFF365314), imageFirst: false, minimal: true),
  EventShareCardDesign(name: 'Indigo', background: Color(0xFF21124A), accent: Color(0xFFC4B5FD)),
];

class EventShareCardDesignPicker extends StatelessWidget {
  const EventShareCardDesignPicker({
    super.key,
    required this.preview,
    required this.onSelected,
  });

  final EventPreviewModel preview;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * .88),
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).padding.bottom + 20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 38, height: 5, decoration: BoxDecoration(color: colors.outlineVariant.withValues(alpha: .8), borderRadius: BorderRadius.circular(8))),
          const SizedBox(height: 14),
          Text('Choisir une carte', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: colors.onSurface)),
          const SizedBox(height: 4),
          Text('10 styles pour présenter cet événement', style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant)),
          const SizedBox(height: 14),
          Expanded(
            child: GridView.builder(
              itemCount: eventShareCardDesigns.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 14,
                childAspectRatio: .59,
              ),
              itemBuilder: (context, index) {
                final design = eventShareCardDesigns[index];
                return GestureDetector(
                  onTap: () => onSelected(index),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: EventShareCardArtwork(preview: preview, designIndex: index, compact: true),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(design.name, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colors.onSurface)),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class EventShareCardArtwork extends StatelessWidget {
  const EventShareCardArtwork({
    super.key,
    required this.preview,
    required this.designIndex,
    this.compact = false,
  });

  final EventPreviewModel preview;
  final int designIndex;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final event = preview.event;
    final design = eventShareCardDesigns[designIndex.clamp(0, eventShareCardDesigns.length - 1).toInt()];
    final foreground = design.minimal ? const Color(0xFF111827) : Colors.white;
    final date = DateFormat('dd/MM/yyyy · HH:mm').format(event.startsAt.toLocal());
    final description = (event.description ?? '').trim();

    Widget cover() => SizedBox(
      width: double.infinity,
      child: event.coverImageUrl != null && event.coverImageUrl!.isNotEmpty
          ? Image.network(event.coverImageUrl!, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _coverFallback(design))
          : _coverFallback(design),
    );

    Widget details() => Padding(
      padding: EdgeInsets.all(compact ? 10 : 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('SCROLE  /  ÉVÉNEMENT', style: TextStyle(color: design.accent, fontSize: compact ? 7 : 14, fontWeight: FontWeight.w900, letterSpacing: 1.4)),
          SizedBox(height: compact ? 7 : 18),
          Text(event.name, maxLines: compact ? 3 : 3, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: foreground, fontSize: compact ? 15 : 37, height: 1.06, fontWeight: FontWeight.w900)),
          SizedBox(height: compact ? 7 : 18),
          _infoLine(Icons.calendar_month_rounded, date, foreground, design.accent, compact),
          const SizedBox(height: 5),
          _infoLine(Icons.location_on_rounded, event.locationDisplay, foreground, design.accent, compact),
          if (description.isNotEmpty) ...[
            SizedBox(height: compact ? 7 : 18),
            Text(description, maxLines: compact ? 3 : 5, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: foreground.withValues(alpha: .82), fontSize: compact ? 8 : 19, height: 1.25)),
          ],
          if (!compact) ...[
            const Spacer(),
            const SizedBox(height: 18),
            Text('Retrouve l’événement sur Scrole', style: TextStyle(color: design.accent, fontSize: 15, fontWeight: FontWeight.bold)),
          ],
        ],
      ),
    );

    return Container(
      width: compact ? double.infinity : 540,
      height: compact ? double.infinity : 960,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: design.background,
        borderRadius: BorderRadius.circular(compact ? 0 : 24),
      ),
      child: design.imageFirst
          ? Column(children: [
              Expanded(flex: compact ? 5 : 6, child: cover()),
              Expanded(flex: compact ? 6 : 7, child: details()),
            ])
          : Column(children: [
              Expanded(flex: compact ? 6 : 7, child: details()),
              Expanded(flex: compact ? 5 : 6, child: cover()),
            ]),
    );
  }

  Widget _coverFallback(EventShareCardDesign design) => Container(
    color: design.accent.withValues(alpha: .16),
    alignment: Alignment.center,
    child: Icon(Icons.event_rounded, color: design.accent, size: compact ? 38 : 100),
  );

  Widget _infoLine(IconData icon, String text, Color foreground, Color accent, bool compact) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: compact ? 11 : 24, color: accent),
      SizedBox(width: compact ? 4 : 10),
      Expanded(child: Text(text.isEmpty ? 'Lieu à confirmer' : text,
        maxLines: compact ? 2 : 2, overflow: TextOverflow.ellipsis,
        style: TextStyle(color: foreground.withValues(alpha: .9), fontSize: compact ? 8 : 18, fontWeight: FontWeight.w600))),
    ],
  );
}

class EventShareCardRenderer {
  static Future<File> renderToFile({
    required BuildContext context,
    required EventPreviewModel preview,
    required int designIndex,
  }) async {
    final key = GlobalKey();
    final overlay = OverlayEntry(
      builder: (_) => Positioned(
        left: -2000,
        top: 0,
        child: Material(
          color: Colors.transparent,
          child: RepaintBoundary(
            key: key,
            child: EventShareCardArtwork(preview: preview, designIndex: designIndex),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(overlay);
    try {
      await Future.delayed(const Duration(milliseconds: 900));
      final boundary = key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('Impossible de préparer la carte de partage.');
      final ui.Image image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) throw StateError('Impossible de convertir la carte en image.');
      final Uint8List bytes = data.buffer.asUint8List();
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/event_card_${preview.event.id}_${designIndex + 1}.png');
      await file.writeAsBytes(bytes, flush: true);
      return file;
    } finally {
      overlay.remove();
    }
  }
}
