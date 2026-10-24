class VoiceMessage {
  final String url;
  final Duration duration;

  const VoiceMessage({
    required this.url,
    required this.duration,
  });

  factory VoiceMessage.fromJson(Map<String, dynamic> json) {
    return VoiceMessage(
      url: (json['url'] ?? json['audio_url'] ?? '').toString(),
      duration: Duration(milliseconds: (json['duration_ms'] as num?)?.toInt() ?? (json['duration'] as num?)?.toInt() ?? 0),
    );
  }

  Map<String, dynamic> toJson() => {
        'url': url,
        'duration_ms': duration.inMilliseconds,
      };
}
