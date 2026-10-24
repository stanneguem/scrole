enum TransferStatus { pending, accepted, rejected, cancelled }

class EventTransferModel {
  final String id;
  final String eventId;
  final String eventName;
  final String proposedBy;
  final String proposerName;
  final String proposedTo;
  final String recipientName;
  final TransferStatus status;
  final DateTime createdAt;
  final DateTime? respondedAt;

  const EventTransferModel({
    required this.id,
    required this.eventId,
    required this.eventName,
    required this.proposedBy,
    required this.proposerName,
    required this.proposedTo,
    required this.recipientName,
    required this.status,
    required this.createdAt,
    this.respondedAt,
  });

  factory EventTransferModel.fromJson(Map<String, dynamic> json) {
    String eName = 'Événement';
    if (json['events'] is Map) {
      eName = (json['events']['name'] ?? json['events']['nom'] ?? 'Événement').toString();
    }

    String propName = 'Proposeur';
    if (json['proposer'] is Map) {
      final p = json['proposer'] as Map;
      final first = (p['first_name'] ?? '').toString();
      final last = (p['last_name'] ?? '').toString();
      final username = (p['username'] ?? '').toString();
      propName = '$first $last'.trim();
      if (propName.isEmpty) propName = username.isNotEmpty ? username : 'Proposeur';
    }

    String recName = 'Destinataire';
    if (json['recipient'] is Map) {
      final p = json['recipient'] as Map;
      final first = (p['first_name'] ?? '').toString();
      final last = (p['last_name'] ?? '').toString();
      final username = (p['username'] ?? '').toString();
      recName = '$first $last'.trim();
      if (recName.isEmpty) recName = username.isNotEmpty ? username : 'Destinataire';
    }

    final statusStr = (json['status'] ?? json['statut'] ?? 'en_attente').toString();
    TransferStatus parsedStatus = TransferStatus.pending;
    if (statusStr == 'acceptee' || statusStr == 'accepted') {
      parsedStatus = TransferStatus.accepted;
    } else if (statusStr == 'refusee' || statusStr == 'rejected') {
      parsedStatus = TransferStatus.rejected;
    } else if (statusStr == 'annulee' || statusStr == 'cancelled') {
      parsedStatus = TransferStatus.cancelled;
    }

    return EventTransferModel(
      id: (json['id'] ?? '').toString(),
      eventId: (json['event_id'] ?? json['evenement_id'] ?? '').toString(),
      eventName: eName,
      proposedBy: (json['proposed_by'] ?? json['propose_par'] ?? '').toString(),
      proposerName: propName,
      proposedTo: (json['proposed_to'] ?? json['propose_a'] ?? '').toString(),
      recipientName: recName,
      status: parsedStatus,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      respondedAt: json['responded_at'] != null
          ? DateTime.tryParse(json['responded_at'].toString())
          : null,
    );
  }
}
