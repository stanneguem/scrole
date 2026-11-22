import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:get/get.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:scrole/app/theme/app_colors.dart';
import 'package:scrole/shared/widgets/app_cached_image.dart';
import 'package:scrole/shared/widgets/user_certified_badge.dart';
import '../../../module_discussion_direct/externe/repositories/social_repository.dart';
import '../controllers/profile_controller.dart';

class ShareProfileScreen extends StatefulWidget {
  const ShareProfileScreen({super.key});

  @override
  State<ShareProfileScreen> createState() => _ShareProfileScreenState();
}

class _ShareProfileScreenState extends State<ShareProfileScreen> {
  final GlobalKey _cardKey = GlobalKey();
  bool _sharing = false;
  bool _loadingQr = true;
  String? _personalQrData;

  ProfileController get _profile => Get.find<ProfileController>();

  @override
  void initState() {
    super.initState();
    _loadPersonalQrCode();
  }

  Future<void> _loadPersonalQrCode() async {
    try {
      final qr = await SocialRepository().getOrGenerateUserQrCode();
      final id = (qr['id'] ?? '').toString();
      if (id.isEmpty) throw StateError('Personal QR identifier is missing');
      if (!mounted) return;
      setState(() {
        _personalQrData = 'scrole_qr:$id';
        _loadingQr = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _personalQrData = null;
        _loadingQr = false;
      });
    }
  }

  String get _profileLink => 'https://scrole.fun/user-profile/${_profile.userId.value}';

  Future<void> _shareLink() async {
    await SharePlus.instance.share(ShareParams(
      text: 'share_profile_link_message'.trParams({
        'name': _profile.displayName,
        'link': _profileLink,
      }),
      subject: 'share_profile_subject'.trParams({'name': _profile.displayName}),
    ));
  }

  Future<void> _shareProfileCard() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final boundary = _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('Profile card is not ready');
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (bytes == null) throw StateError('Could not render profile card');
      final directory = await Directory.systemTemp.createTemp('scrole_profile_share_');
      final file = File('${directory.path}/scrole_profile.png');
      await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'image/png')],
        text: 'share_profile_card_message'.trParams({'name': _profile.displayName, 'link': _profileLink}),
        subject: 'share_profile_subject'.trParams({'name': _profile.displayName}),
      ));
    } catch (e) {
      if (mounted) Get.snackbar('error_title'.tr, 'share_profile_error'.tr, snackPosition: SnackPosition.BOTTOM);
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        title: Text('share_profile_title'.tr, style: const TextStyle(fontWeight: FontWeight.w800)),
        centerTitle: true,
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            Text('share_profile_intro'.tr, style: TextStyle(color: colors.onSurfaceVariant, fontSize: 14, height: 1.45)),
            const SizedBox(height: 22),
            RepaintBoundary(
              key: _cardKey,
              child: _ProfileShareCard(profile: _profile, link: _profileLink, personalQrData: _personalQrData, loadingQr: _loadingQr),
            ),
            const SizedBox(height: 24),
            _ShareOptionTile(
              icon: Icons.link_rounded,
              title: 'share_profile_link_title'.tr,
              subtitle: 'share_profile_link_subtitle'.tr,
              onTap: _shareLink,
            ),
            const SizedBox(height: 10),
            _ShareOptionTile(
              icon: Icons.image_outlined,
              title: 'share_profile_card_title'.tr,
              subtitle: 'share_profile_card_subtitle'.tr,
              onTap: _shareProfileCard,
              loading: _sharing,
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileShareCard extends StatelessWidget {
  const _ProfileShareCard({required this.profile, required this.link, required this.personalQrData, required this.loadingQr});
  final ProfileController profile;
  final String link;
  final String? personalQrData;
  final bool loadingQr;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF161B33), Color(0xFF542C79), Color(0xFFDB4E79)],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [BoxShadow(color: colors.shadow.withValues(alpha: .16), blurRadius: 22, offset: const Offset(0, 12))],
      ),
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(width: 34, height: 34, padding: const EdgeInsets.all(3), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)), child: Image.asset('assets/logos/img.png', fit: BoxFit.contain)),
            const SizedBox(width: 9),
            const Text('SCROLE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 13)),
            const Spacer(),
          ]),
          const SizedBox(height: 28),
          Center(
            child: Container(
              width: 94,
              height: 94,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: .2), shape: BoxShape.circle, border: Border.all(color: Colors.white.withValues(alpha: .7), width: 1.5)),
              child: ClipOval(
                child: profile.profileImageUrl.value.isEmpty
                    ? Container(color: Colors.white.withValues(alpha: .15), child: Center(child: Text(profile.initials, style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800))))
                    : AppCachedImage(imageUrl: profile.profileImageUrl.value, fit: BoxFit.cover),
              ),
            ),
          ),
          const SizedBox(height: 15),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: Text(profile.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800))),
                if (profile.isVerified.value) ...[
                  const SizedBox(width: 6),
                  UserCertifiedBadge(size: 21, userId: profile.userId.value),
                ],
              ],
            ),
          ),
          const SizedBox(height: 4),
          Center(child: Text('@${profile.username.value}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withValues(alpha: .78), fontSize: 14))),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ProfileMetric(value: profile.followersCount.value.toString(), label: 'share_profile_followers'.tr),
              Container(width: 1, height: 28, margin: const EdgeInsets.symmetric(horizontal: 14), color: Colors.white.withValues(alpha: .3)),
              _ProfileMetric(value: profile.followingCount.value.toString(), label: 'share_profile_following'.tr),
              Container(width: 1, height: 28, margin: const EdgeInsets.symmetric(horizontal: 14), color: Colors.white.withValues(alpha: .3)),
              _ProfileMetric(value: profile.reputation.value.toStringAsFixed(1), label: 'share_profile_reputation'.tr),
            ],
          ),
          const SizedBox(height: 24),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('share_profile_card_caption'.tr, style: TextStyle(color: Colors.white.withValues(alpha: .86), fontSize: 12)),
              const SizedBox(height: 5),
              Text('Scrole', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17)),
            ])),
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: loadingQr
                  ? const SizedBox(width: 70, height: 70, child: Padding(padding: EdgeInsets.all(22), child: CircularProgressIndicator(strokeWidth: 2)))
                  : personalQrData == null
                      ? const SizedBox(width: 70, height: 70, child: Icon(Icons.qr_code_2_rounded, size: 48, color: Colors.black54))
                      : QrImageView(data: personalQrData!, size: 70, backgroundColor: Colors.white),
            ),
          ]),
        ],
      ),
    );
  }
}

class _ProfileMetric extends StatelessWidget {
  const _ProfileMetric({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17)),
      const SizedBox(height: 3),
      Text(label, style: TextStyle(color: Colors.white.withValues(alpha: .78), fontSize: 11)),
    ],
  );
}

class _ShareOptionTile extends StatelessWidget {
  const _ShareOptionTile({required this.icon, required this.title, required this.subtitle, required this.onTap, this.loading = false});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: loading ? null : onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(children: [
            Container(width: 46, height: 46, decoration: BoxDecoration(color: colors.primary.withValues(alpha: .12), borderRadius: BorderRadius.circular(15)), child: Icon(icon, color: colors.primary, size: 23)),
            const SizedBox(width: 13),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(color: colors.onSurface, fontWeight: FontWeight.w800, fontSize: 14)),
              const SizedBox(height: 4),
              Text(subtitle, style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12, height: 1.35)),
            ])),
            if (loading) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            else Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant),
          ]),
        ),
      ),
    );
  }
}
