/// Supported memory categories in Listen to Eve.
///
/// Follows AGENTS.md Rule 6 memory hierarchy:
/// - [semantic]: factual knowledge and user facts
/// - [preference]: personal preferences, tone, style, and voice choices
/// - [episodic]: memorable events, conversations, and experiences
/// - [relationship]: interpersonal dynamics, shared context, and user background
/// - [skill]: acquired abilities, tasks, domains, or instructions
enum MemoryCategory {
  semantic,
  preference,
  episodic,
  relationship,
  skill;

  static MemoryCategory fromString(String val) {
    switch (val.toLowerCase().trim()) {
      case 'preference':
        return MemoryCategory.preference;
      case 'episodic':
      case 'goal':
        return MemoryCategory.episodic;
      case 'relationship':
      case 'health':
        return MemoryCategory.relationship;
      case 'skill':
        return MemoryCategory.skill;
      case 'semantic':
      case 'fact':
      default:
        return MemoryCategory.semantic;
    }
  }

  String get displayName {
    switch (this) {
      case MemoryCategory.semantic:
        return 'Semantic';
      case MemoryCategory.preference:
        return 'Preference';
      case MemoryCategory.episodic:
        return 'Episodic';
      case MemoryCategory.relationship:
        return 'Relationship';
      case MemoryCategory.skill:
        return 'Skill';
    }
  }

  String displayNameAf(bool isAf) {
    if (!isAf) return displayName;
    switch (this) {
      case MemoryCategory.semantic:
        return 'Semanties';
      case MemoryCategory.preference:
        return 'Voorkeur';
      case MemoryCategory.episodic:
        return 'Episodies';
      case MemoryCategory.relationship:
        return 'Verhouding';
      case MemoryCategory.skill:
        return 'Vaardigheid';
    }
  }
}

/// Represents a persistent user memory item in Listen to Eve.
class MemoryItem {
  final String id;
  final String content;
  final MemoryCategory category;
  final int importance; // 1 (low) to 5 (critical)
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastAccessedAt;
  final int accessCount;

  /// Optional character ID to associate character-specific relationship memory (e.g. 'eve', 'ara').
  /// If null or empty, this memory is global and shared across all characters.
  final String? characterId;

  /// Optional topic key to identify the subject (e.g. 'user_name', 'residence', 'favorite_color').
  /// Enables contradiction detection and consolidation without embeddings.
  final String? topicKey;

  MemoryItem({
    required this.id,
    required this.content,
    required this.category,
    this.importance = 3,
    required this.createdAt,
    required this.updatedAt,
    this.lastAccessedAt,
    this.accessCount = 0,
    this.characterId,
    this.topicKey,
  });

  bool get isGlobal => characterId == null || characterId!.isEmpty;

  MemoryItem copyWith({
    String? id,
    String? content,
    MemoryCategory? category,
    int? importance,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastAccessedAt,
    int? accessCount,
    String? characterId,
    bool clearCharacterId = false,
    String? topicKey,
    bool clearTopicKey = false,
  }) {
    return MemoryItem(
      id: id ?? this.id,
      content: content ?? this.content,
      category: category ?? this.category,
      importance: importance ?? this.importance,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastAccessedAt: lastAccessedAt ?? this.lastAccessedAt,
      accessCount: accessCount ?? this.accessCount,
      characterId: clearCharacterId ? null : (characterId ?? this.characterId),
      topicKey: clearTopicKey ? null : (topicKey ?? this.topicKey),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'content': content,
        'category': category.name,
        'importance': importance,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'lastAccessedAt': lastAccessedAt?.toIso8601String(),
        'accessCount': accessCount,
        if (characterId != null) 'characterId': characterId,
        if (topicKey != null) 'topicKey': topicKey,
      };

  factory MemoryItem.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return MemoryItem(
      id: json['id'] as String? ?? now.millisecondsSinceEpoch.toString(),
      content: json['content'] as String? ?? '',
      category: MemoryCategory.fromString(
        (json['category'] ?? json['type']) as String? ?? 'semantic',
      ),
      importance: (json['importance'] as num?)?.toInt() ?? 3,
      createdAt: json['createdAt'] != null
          ? (DateTime.tryParse(json['createdAt'] as String) ?? now)
          : now,
      updatedAt: json['updatedAt'] != null
          ? (DateTime.tryParse(json['updatedAt'] as String) ?? now)
          : now,
      lastAccessedAt: json['lastAccessedAt'] != null
          ? DateTime.tryParse(json['lastAccessedAt'] as String)
          : null,
      accessCount: (json['accessCount'] as num?)?.toInt() ?? 0,
      characterId: json['characterId'] as String?,
      topicKey: json['topicKey'] as String?,
    );
  }
}
