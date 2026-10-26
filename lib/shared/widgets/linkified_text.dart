import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Renders URLs as tappable links while preserving normal text and entity mentions.
class LinkifiedText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow overflow;
  final TextAlign textAlign;
  final Color? linkColor;
  final ValueChanged<String>? onHashtagTap;

  const LinkifiedText({
    super.key,
    required this.text,
    this.style,
    this.maxLines,
    this.overflow = TextOverflow.clip,
    this.textAlign = TextAlign.start,
    this.linkColor,
    this.onHashtagTap,
  });

  @override
  State<LinkifiedText> createState() => _LinkifiedTextState();
}

class _LinkifiedTextState extends State<LinkifiedText> {
  final List<TapGestureRecognizer> _recognizers = [];

  // Handles explicit URLs, www links and common bare domains.
  static final RegExp _tokenPattern = RegExp(
    r'#[\p{L}\p{N}_]+|https?://[^\s<>{}]+|www\.[^\s<>{}]+|(?:[A-Za-z0-9-]+\.)+[A-Za-z]{2,}(?:/[^\s<>{}]*)?|@[A-Za-z0-9_.]+|[*~]\{[^}]+\}',
    caseSensitive: false,
  );

  @override
  void dispose() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
    super.dispose();
  }

  String _trimUrlPunctuation(String value) {
    var result = value;
    while (result.isNotEmpty && RegExp(r'[.,!?;:)]$').hasMatch(result)) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();

    final theme = Theme.of(context);
    final baseStyle = widget.style ?? DefaultTextStyle.of(context).style;
    final linkStyle = baseStyle.copyWith(
      color: widget.linkColor ?? theme.colorScheme.primary,
      decoration: TextDecoration.underline,
      decorationColor: widget.linkColor ?? theme.colorScheme.primary,
    );
    final spans = <InlineSpan>[];
    var cursor = 0;

    for (final match in _tokenPattern.allMatches(widget.text)) {
      var token = match.group(0)!;
      final isMention = token.startsWith('@') || token.startsWith('*{') || token.startsWith('~{');
      final isHashtag = token.startsWith('#');
      if (match.start > cursor) {
        spans.add(TextSpan(text: widget.text.substring(cursor, match.start), style: baseStyle));
      }

      if (isHashtag) {
        final tagStyle = baseStyle.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w600);
        final recognizer = widget.onHashtagTap == null ? null : (TapGestureRecognizer()..onTap = () => widget.onHashtagTap!(token.substring(1)));
        if (recognizer != null) _recognizers.add(recognizer);
        spans.add(TextSpan(text: token, style: tagStyle, recognizer: recognizer));
        cursor = match.end;
        continue;
      }

      if (isMention) {
        final display = token.startsWith('*{') || token.startsWith('~{')
            ? token.substring(2, token.length - 1)
            : token;
        spans.add(TextSpan(
          text: display,
          style: baseStyle.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ));
        cursor = match.end;
        continue;
      }

      final trimmed = _trimUrlPunctuation(token);
      final suffix = token.substring(trimmed.length);
      if (trimmed.isEmpty) {
        spans.add(TextSpan(text: token, style: baseStyle));
        cursor = match.end;
        continue;
      }
      final recognizer = TapGestureRecognizer()
        ..onTap = () async {
          final normalized = trimmed.startsWith('www.')
              ? 'https://$trimmed'
              : (trimmed.contains('://') ? trimmed : 'https://$trimmed');
          final uri = Uri.tryParse(normalized);
          if (uri == null || !{'http', 'https'}.contains(uri.scheme) || uri.host.isEmpty) return;
          try {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          } catch (error) {
            debugPrint('[LINK] Could not open $uri: $error');
          }
        };
      _recognizers.add(recognizer);
      spans.add(TextSpan(text: trimmed, style: linkStyle, recognizer: recognizer));
      if (suffix.isNotEmpty) spans.add(TextSpan(text: suffix, style: baseStyle));
      cursor = match.end;
    }

    if (cursor < widget.text.length) {
      spans.add(TextSpan(text: widget.text.substring(cursor), style: baseStyle));
    }
    if (spans.isEmpty) spans.add(TextSpan(text: widget.text, style: baseStyle));

    return RichText(
      text: TextSpan(style: baseStyle, children: spans),
      maxLines: widget.maxLines,
      overflow: widget.overflow,
      textAlign: widget.textAlign,
      textDirection: Directionality.of(context),
    );
  }
}
