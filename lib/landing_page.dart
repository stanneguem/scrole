import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});
  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage>
    with TickerProviderStateMixin {
  late final AnimationController _fadeCtrl;
  late final AnimationController _floatCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<double> _floatAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _floatCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat(reverse: true);
    _floatAnim = Tween<double>(
      begin: -8,
      end: 8,
    ).animate(CurvedAnimation(parent: _floatCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _floatCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final isWide = w >= 1100;

    return Scaffold(
      backgroundColor: const Color(0xFF0C0D10),
      body: Stack(
        children: [
          // ── Ambient glows ─────────────────────────────────────────────
          const Positioned(
            top: -150,
            left: -100,
            child: _Blob(color: Color(0x1F6B8CFF), size: 600),
          ),
          const Positioned(
            bottom: -120,
            right: -80,
            child: _Blob(color: Color(0x12B46BFF), size: 500),
          ),
          const Positioned(
            top: 300,
            right: -60,
            child: _Blob(color: Color(0x0CA855F7), size: 350),
          ),

          // ── Scroll ────────────────────────────────────────────────────
          FadeTransition(
            opacity: _fadeAnim,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // ── NAV ──────────────────────────────────────────────────
                  _NavBar(),

                  // ── HERO ─────────────────────────────────────────────────
                  _HeroSection(isWide: isWide, floatAnim: _floatAnim),

                  // ── BANNER "non disponible" ───────────────────────────────
                  _UnavailableBanner(),

                  // ── FEATURES ─────────────────────────────────────────────
                  _FeaturesSection(),

                  // ── ROADMAP ───────────────────────────────────────────────
                  _RoadmapSection(),

                  // ── CTA final ────────────────────────────────────────────
                  _CtaSection(floatAnim: _floatAnim),

                  // ── FOOTER ───────────────────────────────────────────────
                  _Footer(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// NAVBAR
// ═════════════════════════════════════════════════════════════════════════════
class _NavBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 18),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0x12FFFFFF))),
      ),
      child: Row(
        children: [
          // Logo
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2A3266), Color(0xFF1A1F3A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0x406B8CFF)),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6B8CFF).withOpacity(0.3),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  'L',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF6B8CFF),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Lumis',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  color: const Color(0xFFF0F0F2),
                ),
              ),
            ],
          ),
          const Spacer(),
          // Tags nav
          const _NavLink(label: 'Fonctionnalités'),
          const SizedBox(width: 28),
          const _NavLink(label: 'Roadmap'),
          const SizedBox(width: 28),
          const _NavLink(label: 'Communauté'),
          const SizedBox(width: 32),
          // CTA
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6B8CFF), Color(0xFF7D9FFF)],
              ),
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6B8CFF).withOpacity(0.4),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Text(
              'Télécharger l\'app',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavLink extends StatelessWidget {
  const _NavLink({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Text(
    label,
    style: const TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w500,
      color: Color(0xFF7A7D8A),
    ),
  );
}

// ═════════════════════════════════════════════════════════════════════════════
// HERO
// ═════════════════════════════════════════════════════════════════════════════
class _HeroSection extends StatelessWidget {
  const _HeroSection({required this.isWide, required this.floatAnim});
  final bool isWide;
  final Animation<double> floatAnim;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isWide ? 100 : 40,
        vertical: 80,
      ),
      child: isWide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: _HeroText()),
                const SizedBox(width: 60),
                _HeroPhone(floatAnim: floatAnim),
              ],
            )
          : Column(
              children: [
                _HeroText(),
                const SizedBox(height: 48),
                _HeroPhone(floatAnim: floatAnim),
              ],
            ),
    );
  }
}

class _HeroText extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0x1F6B8CFF),
            borderRadius: BorderRadius.circular(50),
            border: Border.all(color: const Color(0x406B8CFF)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('✨', style: TextStyle(fontSize: 12)),
              SizedBox(width: 6),
              Text(
                'Le réseau social des événements',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF6B8CFF),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        // Titre
        RichText(
          text: TextSpan(
            style: GoogleFonts.spaceGrotesk(
              fontSize: 48,
              fontWeight: FontWeight.w800,
              height: 1.1,
              letterSpacing: -1.5,
              color: const Color(0xFFF0F0F2),
            ),
            children: const [
              TextSpan(text: 'Découvrez,\npartagez et\nvivez des '),
              TextSpan(
                text: 'événements\ninoubliables',
                style: TextStyle(color: Color(0xFF6B8CFF)),
              ),
              TextSpan(text: ' .'),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Lumis connecte les passionnés d\'événements autour d\'eux.\nCalendrier intelligent, découverte personnalisée, communauté vivante.',
          style: TextStyle(
            fontSize: 16,
            height: 1.65,
            color: Color(0xFF7A7D8A),
          ),
        ),
        const SizedBox(height: 36),
        // Boutons
        Row(
          children: [
            _HeroBtn(label: '📱 Disponible sur mobile', filled: true),
            const SizedBox(width: 14),
            _HeroBtn(label: 'En savoir plus →', filled: false),
          ],
        ),
        const SizedBox(height: 40),
        // Stats
        Row(
          children: const [
            _HeroStat(value: '12k+', label: 'Événements'),
            SizedBox(width: 36),
            _HeroStat(value: '48k+', label: 'Membres'),
            SizedBox(width: 36),
            _HeroStat(value: '4.9★', label: 'Note App'),
          ],
        ),
      ],
    );
  }
}

class _HeroBtn extends StatelessWidget {
  const _HeroBtn({required this.label, required this.filled});
  final String label;
  final bool filled;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
    decoration: BoxDecoration(
      gradient: filled
          ? const LinearGradient(colors: [Color(0xFF6B8CFF), Color(0xFF7D9FFF)])
          : null,
      color: filled ? null : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      border: filled ? null : Border.all(color: const Color(0x2EFFFFFF)),
      boxShadow: filled
          ? [
              BoxShadow(
                color: const Color(0xFF6B8CFF).withOpacity(0.4),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ]
          : null,
    ),
    child: Text(
      label,
      style: GoogleFonts.spaceGrotesk(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: filled ? Colors.white : const Color(0xFF7A7D8A),
      ),
    ),
  );
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.value, required this.label});
  final String value, label;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        value,
        style: GoogleFonts.spaceGrotesk(
          fontSize: 24,
          fontWeight: FontWeight.w800,
          color: Color(0xFFF0F0F2),
        ),
      ),
      Text(
        label,
        style: const TextStyle(fontSize: 12, color: Color(0xFF7A7D8A)),
      ),
    ],
  );
}

// HERO PHONE MOCKUP
class _HeroPhone extends StatelessWidget {
  const _HeroPhone({required this.floatAnim});
  final Animation<double> floatAnim;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: floatAnim,
      builder: (_, child) =>
          Transform.translate(offset: Offset(0, floatAnim.value), child: child),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Halo glow
          Container(
            width: 340,
            height: 340,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  const Color(0xFF6B8CFF).withOpacity(0.15),
                  Colors.transparent,
                ],
              ),
            ),
          ),

          // Phone outer
          Container(
            width: 200,
            height: 380,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1C1F27), Color(0xFF0C0D10)],
              ),
              borderRadius: BorderRadius.circular(36),
              border: Border.all(
                color: const Color(0xFF6B8CFF).withOpacity(0.4),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6B8CFF).withOpacity(0.25),
                  blurRadius: 40,
                  offset: const Offset(0, 12),
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 30,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: [
                const SizedBox(height: 16),
                // Notch
                Container(
                  width: 60,
                  height: 6,
                  decoration: BoxDecoration(
                    color: const Color(0xFF6B8CFF).withOpacity(0.3),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(height: 12),
                // Screen content
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0C0D10),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: const Color(0x12FFFFFF)),
                    ),
                    clipBehavior: Clip.hardEdge,
                    child: Column(
                      children: [
                        // App bar mini
                        Container(
                          padding: const EdgeInsets.all(12),
                          color: const Color(0xFF13151A),
                          child: Row(
                            children: [
                              Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFF2A3266),
                                      Color(0xFF1A1F3A),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(7),
                                  border: Border.all(
                                    color: const Color(0x406B8CFF),
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  'L',
                                  style: GoogleFonts.spaceGrotesk(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF6B8CFF),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Lumis',
                                style: GoogleFonts.spaceGrotesk(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFFF0F0F2),
                                ),
                              ),
                              const Spacer(),
                              Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1C1F27),
                                  borderRadius: BorderRadius.circular(7),
                                ),
                                child: const Icon(
                                  Icons.notifications_outlined,
                                  size: 12,
                                  color: Color(0xFF7A7D8A),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Event cards mini
                        Expanded(
                          child: SingleChildScrollView(
                            physics: const NeverScrollableScrollPhysics(),
                            child: Column(
                              children: [
                                const SizedBox(height: 8),
                                for (final e in _miniEvents)
                                  _MiniCard(event: e),
                                const SizedBox(height: 8),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Badge flottant "🔥 Populaire"
          Positioned(
            top: 40,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF13151A),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFFF87171).withOpacity(0.4),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.4),
                    blurRadius: 12,
                  ),
                ],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('🔥', style: TextStyle(fontSize: 12)),
                  SizedBox(width: 4),
                  Text(
                    '1.2k participants',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFF87171),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Badge "👑 Élite"
          Positioned(
            bottom: 60,
            left: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF13151A),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFFFBBF24).withOpacity(0.4),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.4),
                    blurRadius: 12,
                  ),
                ],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('👑', style: TextStyle(fontSize: 12)),
                  SizedBox(width: 4),
                  Text(
                    'Événement Élite',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFFBBF24),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const _miniEvents = [
  ('🎵', 'Nuit Électronique', 'Paris 12e', '🔥', '35€'),
  ('🌸', 'Japan Expo 2026', 'Villepinte', '👑', '25€'),
  ('🎸', 'Dream Theater', 'Accor Arena', '🔥', '45€'),
];

class _MiniCard extends StatelessWidget {
  const _MiniCard({required this.event});
  final (String, String, String, String, String) event;
  @override
  Widget build(BuildContext context) {
    final (emoji, title, loc, tier, price) = event;
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF13151A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x12FFFFFF)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: const Color(0xFF1C1F27),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(emoji, style: const TextStyle(fontSize: 14)),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFF0F0F2),
                  ),
                ),
                Text(
                  '📍 $loc',
                  style: const TextStyle(fontSize: 8, color: Color(0xFF7A7D8A)),
                ),
              ],
            ),
          ),
          Text(
            price,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: Color(0xFFFBBF24),
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// BANNER "NON DISPONIBLE"
// ═════════════════════════════════════════════════════════════════════════════
class _UnavailableBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 40),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF13151A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFBBF24).withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFBBF24).withOpacity(0.08),
            blurRadius: 24,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFFBBF24).withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: const Color(0xFFFBBF24).withOpacity(0.3),
              ),
            ),
            alignment: Alignment.center,
            child: const Text('📱', style: TextStyle(fontSize: 22)),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cette page s\'affiche car tu utilises un écran trop grand',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFF0F0F2),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Lumis est actuellement disponible sur mobile uniquement. Pour profiter de toutes les fonctionnalités, connecte-toi depuis ton téléphone.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: Color(0xFF7A7D8A),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFBBF24).withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: const Color(0xFFFBBF24).withOpacity(0.35),
              ),
            ),
            child: const Text(
              '→ Télécharger',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFFFBBF24),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// FEATURES
// ═════════════════════════════════════════════════════════════════════════════
class _FeaturesSection extends StatelessWidget {
  static const _features = [
    (
      '📅',
      'Calendrier intelligent',
      'Visualise tous les événements près de toi sur un calendrier interactif avec emojis et indicateurs de popularité.',
      Color(0xFF6B8CFF),
    ),
    (
      '🔥',
      'Découverte personnalisée',
      'Algorithme de recommandation basé sur tes goûts, ton historique et ta localisation. Jamais deux soirées pareilles.',
      Color(0xFFF87171),
    ),
    (
      '👑',
      'Événements Élite',
      'Accède à des expériences exclusives et prestigieuses réservées aux membres premium de la communauté Lumis.',
      Color(0xFFFBBF24),
    ),
    (
      '💬',
      'Communauté vivante',
      'Échange avec d\'autres passionnés, crée des groupes autour de tes événements favoris et partage tes expériences.',
      Color(0xFF4ADE80),
    ),
    (
      '🎟',
      'Billetterie intégrée',
      'Achète et gère tes billets directement dans l\'app. Rappels automatiques, QR code, tout est centralisé.',
      Color(0xFFA78BFA),
    ),
    (
      '📍',
      'Géolocalisation',
      'Trouve instantanément les événements autour de toi, même en déplacement. La carte s\'adapte en temps réel.',
      Color(0xFF38BDF8),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final cols = w >= 1100 ? 3 : 2;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 80),
      child: Column(
        children: [
          // Header
          const _SectionLabel(emoji: '✦', label: 'FONCTIONNALITÉS'),
          const SizedBox(height: 16),
          Text(
            'Tout ce que tu attends\nd\'une app événements',
            textAlign: TextAlign.center,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 36,
              fontWeight: FontWeight.w800,
              letterSpacing: -1,
              height: 1.15,
              color: const Color(0xFFF0F0F2),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Disponible sur mobile · Tablette et Desktop bientôt',
            style: TextStyle(fontSize: 14, color: Color(0xFF7A7D8A)),
          ),
          const SizedBox(height: 52),
          // Grille
          _FeatureGrid(features: _features, cols: cols),
        ],
      ),
    );
  }
}

class _FeatureGrid extends StatelessWidget {
  const _FeatureGrid({required this.features, required this.cols});
  final List<(String, String, String, Color)> features;
  final int cols;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, c) {
        final itemW = (c.maxWidth - (cols - 1) * 16) / cols;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: features.map((f) {
            final (emoji, title, desc, color) = f;
            return SizedBox(
              width: itemW,
              child: _FeatureCard(
                emoji: emoji,
                title: title,
                desc: desc,
                color: color,
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _FeatureCard extends StatefulWidget {
  const _FeatureCard({
    required this.emoji,
    required this.title,
    required this.desc,
    required this.color,
  });
  final String emoji, title, desc;
  final Color color;
  @override
  State<_FeatureCard> createState() => _FeatureCardState();
}

class _FeatureCardState extends State<_FeatureCard> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _hovered ? const Color(0xFF13151A) : const Color(0xFF0C0D10),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _hovered
                ? widget.color.withOpacity(0.35)
                : const Color(0x12FFFFFF),
          ),
          boxShadow: _hovered
              ? [
                  BoxShadow(
                    color: widget.color.withOpacity(0.1),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: widget.color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: widget.color.withOpacity(0.25)),
              ),
              alignment: Alignment.center,
              child: Text(widget.emoji, style: const TextStyle(fontSize: 22)),
            ),
            const SizedBox(height: 16),
            Text(
              widget.title,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Color(0xFFF0F0F2),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.desc,
              style: const TextStyle(
                fontSize: 13,
                height: 1.6,
                color: Color(0xFF7A7D8A),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: const Color(0xFF4ADE80).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(
                      color: const Color(0xFF4ADE80).withOpacity(0.3),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.check_rounded,
                    size: 11,
                    color: Color(0xFF4ADE80),
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  'Disponible sur mobile',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF4ADE80),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// ROADMAP
// ═════════════════════════════════════════════════════════════════════════════
class _RoadmapSection extends StatelessWidget {
  static const _steps = [
    (
      '✅',
      'Maintenant',
      'Application Mobile',
      'iOS & Android',
      'Toutes les fonctionnalités core disponibles sur téléphone.',
      Color(0xFF4ADE80),
      true,
    ),
    (
      '🔨',
      'Q3 2026',
      'Version Tablette',
      'iPad & Android Tablet',
      'Interface optimisée pour grand écran, mode split-view et calendrier étendu.',
      Color(0xFF6B8CFF),
      false,
    ),
    (
      '🚀',
      'Q1 2027',
      'Version Desktop',
      'Web & Electron',
      'Expérience complète sur navigateur et application desktop native.',
      Color(0xFFA78BFA),
      false,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 80),
      decoration: const BoxDecoration(
        border: Border.symmetric(
          horizontal: BorderSide(color: Color(0x12FFFFFF)),
        ),
      ),
      child: Column(
        children: [
          const _SectionLabel(emoji: '🗺', label: 'ROADMAP'),
          const SizedBox(height: 16),
          Text(
            'Bientôt disponible\nsur tous vos écrans',
            textAlign: TextAlign.center,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 36,
              fontWeight: FontWeight.w800,
              letterSpacing: -1,
              height: 1.15,
              color: const Color(0xFFF0F0F2),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Nous travaillons dur pour vous offrir la meilleure expérience possible,\nquelle que soit la taille de votre écran.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.6,
              color: Color(0xFF7A7D8A),
            ),
          ),
          const SizedBox(height: 60),
          // Timeline
          LayoutBuilder(
            builder: (_, c) {
              final isWide = c.maxWidth > 800;
              return isWide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: _steps.asMap().entries.expand((e) {
                        final (
                          checkEmoji,
                          period,
                          title,
                          sub,
                          desc,
                          color,
                          done,
                        ) = e.value;
                        final isLast = e.key == _steps.length - 1;
                        return [
                          Expanded(
                            child: _RoadmapCard(
                              checkEmoji: checkEmoji,
                              period: period,
                              title: title,
                              sub: sub,
                              desc: desc,
                              color: color,
                              done: done,
                            ),
                          ),
                          if (!isLast) _RoadmapArrow(),
                        ];
                      }).toList(),
                    )
                  : Column(
                      children: _steps.map((s) {
                        final (
                          checkEmoji,
                          period,
                          title,
                          sub,
                          desc,
                          color,
                          done,
                        ) = s;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: _RoadmapCard(
                            checkEmoji: checkEmoji,
                            period: period,
                            title: title,
                            sub: sub,
                            desc: desc,
                            color: color,
                            done: done,
                          ),
                        );
                      }).toList(),
                    );
            },
          ),
        ],
      ),
    );
  }
}

class _RoadmapArrow extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 32),
    child: const Icon(
      Icons.chevron_right_rounded,
      color: Color(0xFF4A4D58),
      size: 28,
    ),
  );
}

class _RoadmapCard extends StatelessWidget {
  const _RoadmapCard({
    required this.checkEmoji,
    required this.period,
    required this.title,
    required this.sub,
    required this.desc,
    required this.color,
    required this.done,
  });
  final String checkEmoji, period, title, sub, desc;
  final Color color;
  final bool done;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF13151A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: done ? color.withOpacity(0.4) : const Color(0x12FFFFFF),
          width: done ? 1.5 : 1,
        ),
        boxShadow: done
            ? [BoxShadow(color: color.withOpacity(0.12), blurRadius: 24)]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(checkEmoji, style: const TextStyle(fontSize: 20)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: color.withOpacity(0.3)),
                ),
                child: Text(
                  period,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Color(0xFFF0F0F2),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            sub,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Color(0xFF7A7D8A),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            desc,
            style: const TextStyle(
              fontSize: 13,
              height: 1.6,
              color: Color(0xFF4A4D58),
            ),
          ),
          if (done) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_rounded, size: 14, color: color),
                  const SizedBox(width: 6),
                  Text(
                    'Disponible maintenant',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// CTA FINAL
// ═════════════════════════════════════════════════════════════════════════════
class _CtaSection extends StatelessWidget {
  const _CtaSection({required this.floatAnim});
  final Animation<double> floatAnim;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(40),
      padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 64),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1C1F27), Color(0xFF13151A)],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0x2EFFFFFF)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6B8CFF).withOpacity(0.08),
            blurRadius: 40,
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Prêt à rejoindre\nla communauté ?',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 36,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1,
                    height: 1.2,
                    color: const Color(0xFFF0F0F2),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Ouvre Lumis sur ton téléphone et rejoins des milliers de passionnés qui découvrent des événements inoubliables chaque jour.',
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.65,
                    color: Color(0xFF7A7D8A),
                  ),
                ),
                const SizedBox(height: 32),
                // Avatars + texte
                Row(
                  children: [
                    SizedBox(
                      height: 36,
                      width: 36 + 3 * 24.0,
                      child: Stack(
                        children: List.generate(
                          4,
                          (i) => Positioned(
                            left: i * 24.0,
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    [
                                      const Color(0xFF2A3266),
                                      const Color(0xFF1A1F3A),
                                    ],
                                    [
                                      const Color(0xFF7C3AED),
                                      const Color(0xFF4C1D95),
                                    ],
                                    [
                                      const Color(0xFF166534),
                                      const Color(0xFF14532D),
                                    ],
                                    [
                                      const Color(0xFF1D4ED8),
                                      const Color(0xFF1E3A8A),
                                    ],
                                  ][i],
                                ),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: const Color(0xFF0C0D10),
                                  width: 2,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                ['A', 'M', 'S', 'J'][i],
                                style: GoogleFonts.spaceGrotesk(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    RichText(
                      text: const TextSpan(
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF7A7D8A),
                        ),
                        children: [
                          TextSpan(
                            text: '48 000+ membres',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFF0F0F2),
                            ),
                          ),
                          TextSpan(text: ' nous ont rejoints'),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                Row(
                  children: [
                    _CtaBtn(
                      label: '📱 Télécharger sur iOS',
                      color: const Color(0xFF6B8CFF),
                    ),
                    const SizedBox(width: 12),
                    _CtaBtn(
                      label: '🤖 Télécharger sur Android',
                      color: const Color(0xFF4ADE80),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 60),
          // Phone 2
          AnimatedBuilder(
            animation: floatAnim,
            builder: (_, child) => Transform.translate(
              offset: Offset(0, -floatAnim.value),
              child: child,
            ),
            child: _SmallPhone(),
          ),
        ],
      ),
    );
  }
}

class _CtaBtn extends StatelessWidget {
  const _CtaBtn({required this.label, required this.color});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
    decoration: BoxDecoration(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withOpacity(0.35)),
    ),
    child: Text(
      label,
      style: GoogleFonts.spaceGrotesk(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: color,
      ),
    ),
  );
}

class _SmallPhone extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    width: 140,
    height: 260,
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF1C1F27), Color(0xFF0C0D10)],
      ),
      borderRadius: BorderRadius.circular(28),
      border: Border.all(
        color: const Color(0xFF6B8CFF).withOpacity(0.35),
        width: 2,
      ),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF6B8CFF).withOpacity(0.2),
          blurRadius: 32,
          offset: const Offset(0, 10),
        ),
      ],
    ),
    child: Column(
      children: [
        const SizedBox(height: 12),
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: const Color(0xFF6B8CFF).withOpacity(0.3),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(8, 0, 8, 10),
            decoration: BoxDecoration(
              color: const Color(0xFF0C0D10),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0x12FFFFFF)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('🗓', style: TextStyle(fontSize: 28)),
                const SizedBox(height: 8),
                Text(
                  'Calendrier',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFF0F0F2),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Juin 2026',
                  style: TextStyle(fontSize: 10, color: Color(0xFF7A7D8A)),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Text('🔥', style: TextStyle(fontSize: 10)),
                    Text('👑', style: TextStyle(fontSize: 10)),
                    Text('⚡', style: TextStyle(fontSize: 10)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

// ═════════════════════════════════════════════════════════════════════════════
// FOOTER
// ═════════════════════════════════════════════════════════════════════════════
class _Footer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0x12FFFFFF))),
      ),
      child: Row(
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2A3266), Color(0xFF1A1F3A)],
                  ),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0x406B8CFF)),
                ),
                alignment: Alignment.center,
                child: Text(
                  'L',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF6B8CFF),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Lumis',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFFF0F0F2),
                ),
              ),
            ],
          ),
          const Spacer(),
          const Text(
            '© 2026 Lumis · Tous droits réservés · Application mobile uniquement',
            style: TextStyle(fontSize: 12, color: Color(0xFF4A4D58)),
          ),
          const Spacer(),
          Row(
            children: const [
              _FooterLink(label: 'Confidentialité'),
              SizedBox(width: 20),
              _FooterLink(label: 'CGU'),
              SizedBox(width: 20),
              _FooterLink(label: 'Contact'),
            ],
          ),
        ],
      ),
    );
  }
}

class _FooterLink extends StatelessWidget {
  const _FooterLink({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Text(
    label,
    style: const TextStyle(fontSize: 12, color: Color(0xFF4A4D58)),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// UTILS
// ─────────────────────────────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.emoji, required this.label});
  final String emoji, label;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
    decoration: BoxDecoration(
      color: const Color(0x1F6B8CFF),
      borderRadius: BorderRadius.circular(50),
      border: Border.all(color: const Color(0x406B8CFF)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 12)),
        const SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.5,
            color: Color(0xFF6B8CFF),
          ),
        ),
      ],
    ),
  );
}

class _Blob extends StatelessWidget {
  const _Blob({required this.color, required this.size});
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(colors: [color, Colors.transparent]),
    ),
  );
}
