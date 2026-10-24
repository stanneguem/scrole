import 'dart:io';

enum MediaType { photo, video }

class MediaAsset {
  final String id;
  final MediaType type;
  final File file;
  final String path;
  final String filename;
  final String? mimeType;
  final Duration? duration;
  final int? size;
  final File? thumbnailFile;
  final Duration? startTime;
  final Duration? endTime;

  const MediaAsset({
    required this.id,
    required this.type,
    required this.file,
    required this.path,
    required this.filename,
    this.mimeType,
    this.duration,
    this.size,
    this.thumbnailFile,
    this.startTime,
    this.endTime,
  });

  MediaAsset copyWith({
    Duration? startTime,
    Duration? endTime,
    File? file,
  }) {
    return MediaAsset(
      id: id,
      type: type,
      file: file ?? this.file,
      path: file != null ? file.path : path,
      filename: filename,
      mimeType: mimeType,
      duration: duration,
      size: size ?? this.size,
      thumbnailFile: thumbnailFile,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
    );
  }
}
