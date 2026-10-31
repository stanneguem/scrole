import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

class CommunityPollComposerScreen extends StatefulWidget {
  const CommunityPollComposerScreen({super.key});

  @override
  State<CommunityPollComposerScreen> createState() => _CommunityPollComposerScreenState();
}

class _CommunityPollComposerScreenState extends State<CommunityPollComposerScreen> {
  final _optionControllers = <TextEditingController>[
    TextEditingController(),
    TextEditingController(),
  ];
  final _explanationController = TextEditingController();
  final _questionController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  File? _questionImage;
  final List<File?> _optionImages = [null, null];
  String _kind = 'single';
  int _durationHours = 24;
  int? _correctIndex;
  int _step = 0;
  bool _saving = false;

  bool get _isQuiz => _kind == 'quiz';
  bool get _isThisOrThat => _kind == 'this_or_that';

  @override
  void dispose() {
    for (final controller in _optionControllers) {
      controller.dispose();
    }
    _explanationController.dispose();
    _questionController.dispose();
    super.dispose();
  }

  void _selectKind(String kind) {
    setState(() {
      _kind = kind;
      if (_isThisOrThat) {
        while (_optionControllers.length > 2) {
          _optionControllers.removeLast().dispose();
          _optionImages.removeLast();
        }
      }
      if (!_isQuiz) _correctIndex = null;
    });
  }

  Future<File?> _pickImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text('poll_image_gallery'.tr),
              subtitle: Text('poll_image_gallery_hint'.tr),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text('poll_image_camera'.tr),
              subtitle: Text('poll_image_camera_hint'.tr),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
          ]),
        ),
      ),
    );
    if (source == null || !mounted) return null;
    final picked = await _imagePicker.pickImage(
      source: source,
      imageQuality: 88,
      maxWidth: 1800,
      maxHeight: 1800,
    );
    return picked == null ? null : File(picked.path);
  }

  Future<void> _pickQuestionImage() async {
    final image = await _pickImage();
    if (image != null && mounted) setState(() => _questionImage = image);
  }

  Future<void> _pickOptionImage(int index) async {
    final image = await _pickImage();
    if (image != null && mounted) setState(() => _optionImages[index] = image);
  }

  void _addOption() {
    if (_optionControllers.length >= 6 || _isThisOrThat) return;
    setState(() { _optionControllers.add(TextEditingController()); _optionImages.add(null); });
  }

  void _removeOption(int index) {
    if (_optionControllers.length <= 2) return;
    final controller = _optionControllers.removeAt(index);
    _optionImages.removeAt(index);
    controller.dispose();
    if (_correctIndex == index) {
      _correctIndex = null;
    } else if (_correctIndex != null && _correctIndex! > index) {
      _correctIndex = _correctIndex! - 1;
    }
    setState(() {});
  }

  bool _validateQuestion() {
    if (_questionController.text.trim().isEmpty) {
      Get.snackbar('poll_question_required'.tr, 'poll_question_required_hint'.tr);
      return false;
    }
    return true;
  }

  bool _validateOptions() {
    final labels = _optionControllers.map((c) => c.text.trim()).toList();
    if (labels.any((label) => label.isEmpty)) {
      Get.snackbar('poll_error_options_incomplete'.tr, 'poll_error_fill_options'.tr);
      return false;
    }
    if (labels.toSet().length != labels.length) {
      Get.snackbar('poll_error_options_duplicate'.tr, 'poll_error_options_unique'.tr);
      return false;
    }
    if (_isQuiz && _correctIndex == null) {
      Get.snackbar('poll_error_correct_required'.tr, 'poll_error_select_correct'.tr);
      return false;
    }
    return true;
  }

  void _next() {
    if (_saving) return;
    if (_step == 1 && !_validateQuestion()) return;
    if (_step == 1 && !_validateOptions()) return;
    if (_step < 2) {
      FocusScope.of(context).unfocus();
      setState(() => _step++);
    } else {
      _submit();
    }
  }

  void _previous() {
    if (_saving) return;
    if (_step == 0) {
      Get.back();
    } else {
      FocusScope.of(context).unfocus();
      setState(() => _step--);
    }
  }

  void _submit() {
    if (_saving || !_validateQuestion() || !_validateOptions()) return;
    setState(() => _saving = true);
    final labels = _optionControllers.map((c) => c.text.trim()).toList();
    final poll = <String, dynamic>{
      'kind': _kind,
      'question': _questionController.text.trim(),
      if (_questionImage != null) 'image_file_path': _questionImage!.path,
      'options': [
        for (var i = 0; i < labels.length; i++) {
          'label': labels[i], 'is_correct': _isQuiz && i == _correctIndex,
          if (_optionImages[i] != null) 'image_file_path': _optionImages[i]!.path,
        },
      ],
      if (!_isQuiz) 'duration_hours': _durationHours,
      if (_isQuiz && _explanationController.text.trim().isNotEmpty)
        'explanation': _explanationController.text.trim(),
    };
    Get.back<Map<String, dynamic>>(result: poll);
  }

  String get _stepTitle => switch (_step) {
    0 => 'poll_step_choose_format'.tr,
    1 => 'poll_step_prepare_answers'.tr,
    _ => _isQuiz ? 'poll_step_finish_quiz'.tr : 'poll_step_duration'.tr,
  };

  String get _stepDescription => switch (_step) {
    0 => 'poll_prompt_choose_type'.tr,
    1 => _isQuiz ? 'poll_prompt_quiz_answers'.tr : 'poll_prompt_simple_choices'.tr,
    _ => _isQuiz ? 'poll_prompt_quiz_explanation'.tr : 'poll_prompt_vote_duration'.tr,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: _step == 0 ? 'poll_close'.tr : 'poll_previous_step'.tr,
          onPressed: _previous,
          icon: Icon(_step == 0 ? Icons.close_rounded : Icons.arrow_back_rounded),
        ),
        title: Text('poll_create_title'.tr),
        centerTitle: false,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      for (var i = 0; i < 3; i++) ...[
                        Expanded(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            height: 4,
                            decoration: BoxDecoration(
                              color: i <= _step ? colors.primary : colors.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                        if (i < 2) const SizedBox(width: 7),
                      ],
                    ],
                  ),
                  const SizedBox(height: 9),
                  Text('poll_step_counter'.trParams({'step': '${_step + 1}'}),
                    style: theme.textTheme.labelSmall?.copyWith(
                      letterSpacing: 1.2, fontWeight: FontWeight.w800, color: colors.primary)),
                ],
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: ListView(
                  key: ValueKey(_step),
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
                  children: [
                    Text(_stepTitle, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -.65, height: 1.12)),
                    const SizedBox(height: 6),
                    Text(_stepDescription, style: theme.textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant, height: 1.4)),
                    const SizedBox(height: 22),
                    if (_step == 0) ...[
                      _KindTile(
                        selected: _kind == 'single',
                        icon: Icons.radio_button_checked_rounded,
                        title: 'poll_kind_single'.tr,
                        subtitle: 'poll_subtitle_single'.tr,
                        accent: colors.primary,
                        onTap: () => _selectKind('single'),
                      ),
                      const SizedBox(height: 10),
                      _KindTile(
                        selected: _kind == 'multiple',
                        icon: Icons.checklist_rounded,
                        title: 'poll_kind_multiple'.tr,
                        subtitle: 'poll_subtitle_multiple'.tr,
                        accent: colors.primary,
                        onTap: () => _selectKind('multiple'),
                      ),
                      const SizedBox(height: 10),
                      _KindTile(
                        selected: _kind == 'quiz',
                        icon: Icons.lightbulb_rounded,
                        title: 'poll_kind_quiz'.tr,
                        subtitle: 'poll_subtitle_quiz'.tr,
                        accent: colors.tertiary,
                        onTap: () => _selectKind('quiz'),
                      ),
                      const SizedBox(height: 10),
                      _KindTile(
                        selected: _isThisOrThat,
                        icon: Icons.compare_arrows_rounded,
                        title: 'poll_kind_this_or_that'.tr,
                        subtitle: 'poll_subtitle_this_or_that'.tr,
                        accent: colors.secondary,
                        onTap: () => _selectKind('this_or_that'),
                      ),
                    ],
                    if (_step == 1) ...[
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: colors.primary.withValues(alpha: .07),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(children: [
                          Icon(_isQuiz ? Icons.lightbulb_outline_rounded : Icons.tips_and_updates_outlined, color: colors.primary),
                          const SizedBox(width: 10),
                          Expanded(child: Text(
                            _isQuiz
                              ? 'poll_hint_quiz_correct'.tr
                              : _isThisOrThat
                                ? 'poll_hint_this_or_that'.tr
                                : _kind == 'multiple'
                                  ? 'poll_hint_multiple'.tr
                                  : 'poll_hint_single'.tr,
                            style: TextStyle(fontSize: 12, height: 1.35, color: colors.onSurfaceVariant))),
                        ]),
                      ),
                      const SizedBox(height: 18),
                      Text('poll_question_label'.tr, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _questionController,
                        textCapitalization: TextCapitalization.sentences,
                        maxLength: 180,
                        minLines: 2,
                        maxLines: 4,
                        decoration: InputDecoration(
                          hintText: 'poll_question_hint'.tr,
                          prefixIcon: const Icon(Icons.help_outline_rounded),
                          alignLabelWithHint: true,
                          filled: true,
                          fillColor: colors.surfaceContainerLow,
                          counterText: '',
                          contentPadding: const EdgeInsets.all(15),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: colors.outlineVariant)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: colors.outlineVariant)),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text('poll_question_image_label'.tr, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: _pickQuestionImage,
                        borderRadius: BorderRadius.circular(18),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: double.infinity,
                          padding: EdgeInsets.all(_questionImage == null ? 20 : 8),
                          decoration: BoxDecoration(
                            color: colors.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: _questionImage == null ? colors.outlineVariant : colors.primary.withValues(alpha: .6), width: _questionImage == null ? 1 : 1.5),
                          ),
                          child: _questionImage == null
                            ? Column(children: [
                                Container(
                                  width: 54, height: 54,
                                  decoration: BoxDecoration(color: colors.primary.withValues(alpha: .10), borderRadius: BorderRadius.circular(16)),
                                  child: Icon(Icons.add_photo_alternate_rounded, size: 27, color: colors.primary),
                                ),
                                const SizedBox(height: 10),
                                Text('poll_image_add'.tr, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                                const SizedBox(height: 4),
                                Text('poll_image_picker_hint'.tr, textAlign: TextAlign.center, style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
                              ])
                            : Stack(children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.file(_questionImage!, width: double.infinity, height: 190, fit: BoxFit.cover),
                                ),
                                Positioned(
                                  top: 8, right: 8,
                                  child: Material(
                                    color: Colors.black.withValues(alpha: .68),
                                    shape: const CircleBorder(),
                                    child: IconButton(
                                      visualDensity: VisualDensity.compact,
                                      tooltip: 'poll_image_remove'.tr,
                                      onPressed: () => setState(() => _questionImage = null),
                                      icon: const Icon(Icons.close_rounded, color: Colors.white),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  left: 8, bottom: 8,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: .68), borderRadius: BorderRadius.circular(20)),
                                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                                      const Icon(Icons.edit_rounded, color: Colors.white, size: 14),
                                      const SizedBox(width: 5),
                                      Text('poll_image_change'.tr, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                                    ]),
                                  ),
                                ),
                              ]),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(child: Text('poll_options_title'.tr, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
                        Text('${_optionControllers.length}/${_isThisOrThat ? 2 : 6}',
                          style: theme.textTheme.labelMedium?.copyWith(color: colors.onSurfaceVariant)),
                      ]),
                      const SizedBox(height: 12),
                      ..._optionControllers.asMap().entries.map((entry) {
                        final index = entry.key;
                        final correct = _isQuiz && _correctIndex == index;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 11),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            Row(children: [
                            if (_isQuiz)
                              Material(
                                color: correct ? Colors.green.withValues(alpha: .12) : colors.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(13),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(13),
                                  onTap: () => setState(() => _correctIndex = index),
                                  child: SizedBox(
                                    width: 46, height: 52,
                                    child: Icon(correct ? Icons.check_circle_rounded : Icons.circle_outlined,
                                      color: correct ? Colors.green : colors.outline, size: 23),
                                  ),
                                ),
                              )
                            else
                              Container(
                                width: 46, height: 52, alignment: Alignment.center,
                                decoration: BoxDecoration(color: colors.surfaceContainerHighest, borderRadius: BorderRadius.circular(13)),
                                child: Text('${index + 1}', style: TextStyle(fontWeight: FontWeight.w800, color: colors.onSurfaceVariant)),
                              ),
                            const SizedBox(width: 9),
                            Expanded(child: TextField(
                              controller: entry.value,
                              textCapitalization: TextCapitalization.sentences,
                              maxLength: 120,
                              decoration: InputDecoration(
                                counterText: '',
                                hintText: 'poll_answer_hint'.trParams({'number': '${index + 1}'}),
                                filled: true,
                                fillColor: colors.surfaceContainerLow,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide(color: colors.outlineVariant)),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide(color: colors.outlineVariant)),
                              ),
                            )),
                            if (_optionControllers.length > 2) ...[
                              const SizedBox(width: 2),
                              IconButton(
                                tooltip: 'poll_remove_answer'.tr,
                                onPressed: () => _removeOption(index),
                                icon: Icon(Icons.remove_circle_outline_rounded, color: colors.error),
                              ),
                            ],
                            ]),
                            const SizedBox(height: 4),
                            Align(alignment: Alignment.centerLeft, child: TextButton.icon(
                              onPressed: () => _pickOptionImage(index),
                              icon: Icon(_optionImages[index] == null ? Icons.add_photo_alternate_outlined : Icons.image_rounded, size: 18),
                              label: Text(_optionImages[index] == null ? 'poll_image_option_add'.tr : 'poll_image_option_added'.tr),
                            )),
                            if (_optionImages[index] != null)
                              Padding(padding: const EdgeInsets.only(left: 55), child: Row(children: [
                                ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.file(_optionImages[index]!, width: 84, height: 64, fit: BoxFit.cover)),
                                IconButton(tooltip: 'Retirer l’image', onPressed: () => setState(() => _optionImages[index] = null), icon: const Icon(Icons.close_rounded)),
                              ])),
                          ]),
                        );
                      }),
                      if (!_isThisOrThat && _optionControllers.length < 6)
                        OutlinedButton.icon(
                          onPressed: _addOption,
                          icon: const Icon(Icons.add_rounded),
                          label: Text('poll_add_answer'.tr),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(46),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                      if (_isQuiz && _correctIndex != null) ...[
                        const SizedBox(height: 12),
                        Row(children: [
                          const Icon(Icons.check_circle_rounded, color: Colors.green, size: 18),
                          const SizedBox(width: 7),
                          Text('poll_correct_answer_set'.trParams({'number': '${_correctIndex! + 1}'}),
                            style: const TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.w700)),
                        ]),
                      ],
                    ],
                    if (_step == 2 && _isQuiz) ...[
                      Container(
                        padding: const EdgeInsets.all(15),
                        decoration: BoxDecoration(
                          color: colors.tertiary.withValues(alpha: .08),
                          borderRadius: BorderRadius.circular(17),
                          border: Border.all(color: colors.tertiary.withValues(alpha: .22)),
                        ),
                        child: Row(children: [
                          Icon(Icons.lightbulb_rounded, color: colors.tertiary, size: 25),
                          const SizedBox(width: 11),
                          Expanded(child: Text('poll_quiz_explanation_info'.tr,
                            style: TextStyle(color: colors.onSurfaceVariant, height: 1.4, fontSize: 13))),
                        ]),
                      ),
                      const SizedBox(height: 20),
                      Text('poll_explanation_title'.tr, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 5),
                      Text('poll_optional'.tr, style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _explanationController,
                        maxLines: 4,
                        maxLength: 500,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          hintText: 'poll_explanation_hint'.tr,
                          filled: true,
                          fillColor: colors.surfaceContainerLow,
                          contentPadding: const EdgeInsets.all(15),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: colors.outlineVariant)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: colors.outlineVariant)),
                        ),
                      ),
                    ],
                    if (_step == 2 && !_isQuiz) ...[
                      Container(
                        padding: const EdgeInsets.all(15),
                        decoration: BoxDecoration(
                          color: colors.primary.withValues(alpha: .07),
                          borderRadius: BorderRadius.circular(17),
                        ),
                        child: Row(children: [
                          Icon(Icons.schedule_rounded, color: colors.primary, size: 25),
                          const SizedBox(width: 11),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('poll_duration_title'.tr, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                            const SizedBox(height: 3),
                            Text('poll_duration_description'.tr,
                              style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant, height: 1.35)),
                          ])),
                        ]),
                      ),
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 9,
                        runSpacing: 9,
                        children: [
                          for (final hours in [1, 6, 12, 24, 48, 72, 168])
                            ChoiceChip(
                              label: Text(hours == 168 ? 'poll_duration_7_days'.tr : hours < 24 ? 'poll_duration_hours'.trParams({'count': '$hours'}) : 'poll_duration_days'.trParams({'count': '${hours ~/ 24}'})),
                              selected: _durationHours == hours,
                              onSelected: (_) => setState(() => _durationHours = hours),
                              showCheckmark: true,
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: colors.surfaceContainerLow, borderRadius: BorderRadius.circular(15)),
                        child: Row(children: [
                          Icon(Icons.lock_clock_outlined, color: colors.onSurfaceVariant),
                          const SizedBox(width: 10),
                          Expanded(child: Text('poll_results_live_info'.tr,
                            style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant, height: 1.4))),
                        ]),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 18),
              decoration: BoxDecoration(
                color: colors.surface,
                border: Border(top: BorderSide(color: colors.outlineVariant.withValues(alpha: .45))),
                boxShadow: [BoxShadow(color: colors.shadow.withValues(alpha: .035), blurRadius: 16, offset: const Offset(0, -4))],
              ),
              child: Row(children: [
                if (_step > 0) ...[
                  Expanded(child: OutlinedButton(
                    onPressed: _saving ? null : _previous,
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50), shape: const StadiumBorder(), elevation: 0),
                    child: Text('poll_back'.tr),
                  )),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: _saving ? null : _next,
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), shape: const StadiumBorder()),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Flexible(
                        child: Text(
                          _step == 2 ? 'poll_add_to_post'.tr : 'poll_continue'.tr,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(_step == 2 ? Icons.check_rounded : Icons.arrow_forward_rounded, size: 19),
                    ]),
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _KindTile extends StatelessWidget {
  const _KindTile({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: selected ? accent.withValues(alpha: .08) : colors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: selected ? accent.withValues(alpha: .85) : colors.outlineVariant.withValues(alpha: .6), width: selected ? 1.5 : 1),
        boxShadow: selected ? [BoxShadow(color: accent.withValues(alpha: .08), blurRadius: 18, offset: const Offset(0, 5))] : const [],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
            child: Row(children: [
              Container(
                width: 50, height: 50,
                decoration: BoxDecoration(
                  color: selected ? accent.withValues(alpha: .14) : colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(icon, color: selected ? accent : colors.onSurfaceVariant, size: 24),
              ),
              const SizedBox(width: 13),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: colors.onSurface)),
                const SizedBox(height: 4),
                Text(subtitle, style: TextStyle(fontSize: 12, height: 1.35, color: colors.onSurfaceVariant)),
              ])),
              const SizedBox(width: 8),
              Icon(selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                color: selected ? accent : colors.outline, size: 22),
            ]),
          ),
        ),
      ),
    );
  }
}
