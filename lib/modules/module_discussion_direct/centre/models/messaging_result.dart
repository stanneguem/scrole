class MessagingResult<T> {
  const MessagingResult._({required this.success, this.data, this.code, this.message});

  final bool success;
  final T? data;
  final String? code;
  final String? message;

  const MessagingResult.success([T? data]) : this._(success: true, data: data);
  const MessagingResult.failure(String code, String message) : this._(success: false, code: code, message: message);
}
