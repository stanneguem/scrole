class VoiceMessage {
  final String fileName;
  final String sizeLabel;
  final String durationLabel;
  final String? url;

  const VoiceMessage({
    this.fileName = '',
    this.sizeLabel = '',
    this.durationLabel = '',
    this.url,
  });

  factory VoiceMessage.fromJson(Map<String, dynamic> json) {
    return VoiceMessage(
      fileName: (json['file_name'] ?? '').toString(),
      sizeLabel: (json['size_label'] ?? '').toString(),
      durationLabel: (json['duration_label'] ?? '').toString(),
      url: json['url']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'file_name': fileName,
        'size_label': sizeLabel,
        'duration_label': durationLabel,
        if (url != null) 'url': url,
      };
}
