export 'message.dart';

import 'message.dart';

/// Compatibility facade required because the two legacy views are intentionally
/// left untouched. All real messaging logic uses [Message].
class MessageModel extends Message {
  const MessageModel({
    required String id,
    String? localId,
    required String conversationId,
    required String senderId,
    String? text,
    List<String>? mediaUrls,
    String? audioUrl,
    Duration? audioDuration,
    MessageType type = MessageType.text,
    required DateTime createdAt,
    MessageStatus status = MessageStatus.sent,
    String? repliedToId,
    DateTime? editedAt,
    bool editedSilently = false,
    DateTime? deletedAt,
    bool deletedSilently = false,
    bool deletedForMe = false,
    bool isDeletedForEveryone = false,
    bool? senderIsCertifiedAtDeletion,
  }) : super(id:id,localId:localId??id,conversationId:conversationId,senderId:senderId,content:text,mediaUrls:mediaUrls,audioUrl:audioUrl,audioDuration:audioDuration,type:type,sentAt:createdAt,status:status,repliedToId:repliedToId,editedAt:editedAt,deletedAt:deletedAt,deletedForMe:deletedForMe,isDeletedForEveryone:isDeletedForEveryone||deletedAt!=null,senderIsCertifiedAtDeletion:senderIsCertifiedAtDeletion);

  factory MessageModel.fromMessage(Message message) => MessageModel(id:message.id,localId:message.localId,conversationId:message.conversationId,senderId:message.senderId,text:message.content,mediaUrls:message.mediaUrls,audioUrl:message.audioUrl,audioDuration:message.audioDuration,type:message.type,createdAt:message.sentAt,status:_compatStatus(message.status),repliedToId:message.repliedToId,editedAt:message.editedAt,deletedAt:message.deletedAt,deletedForMe:message.deletedForMe,isDeletedForEveryone:message.isDeletedForEveryone,senderIsCertifiedAtDeletion:message.senderIsCertifiedAtDeletion);

  static MessageStatus _compatStatus(MessageStatus status) => switch(status){MessageStatus.pending=>MessageStatus.sending,MessageStatus.failed=>MessageStatus.error,MessageStatus.delivered=>MessageStatus.received,_=>status};
}
