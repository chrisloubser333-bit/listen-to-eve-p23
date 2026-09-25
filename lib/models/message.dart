enum MessageRole { user, assistant, system }

class ChatMessage {
  final String id;
  final MessageRole role;
  final String content;
  final DateTime timestamp;
  final bool isVoice;
  final String? audioPath; // local path if voice message was recorded/played
  final String? imageUrl; // url or asset path or base64 data for generated/uploaded images
  final String? imagePrompt; // original prompt that generated the image

  bool get isImage => imageUrl != null && imageUrl!.isNotEmpty;

  ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
    this.isVoice = false,
    this.audioPath,
    this.imageUrl,
    this.imagePrompt,
  });

  ChatMessage copyWith({
    String? id,
    MessageRole? role,
    String? content,
    DateTime? timestamp,
    bool? isVoice,
    String? audioPath,
    String? imageUrl,
    String? imagePrompt,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      isVoice: isVoice ?? this.isVoice,
      audioPath: audioPath ?? this.audioPath,
      imageUrl: imageUrl ?? this.imageUrl,
      imagePrompt: imagePrompt ?? this.imagePrompt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role.name,
        'content': content,
        'timestamp': timestamp.toIso8601String(),
        'isVoice': isVoice,
        'audioPath': audioPath,
        'imageUrl': imageUrl,
        'imagePrompt': imagePrompt,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String,
      role: MessageRole.values.firstWhere(
        (e) => e.name == json['role'],
        orElse: () => MessageRole.user,
      ),
      content: json['content'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      isVoice: json['isVoice'] as bool? ?? false,
      audioPath: json['audioPath'] as String?,
      imageUrl: json['imageUrl'] as String?,
      imagePrompt: json['imagePrompt'] as String?,
    );
  }
}
