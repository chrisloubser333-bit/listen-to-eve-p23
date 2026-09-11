import '../models/memory_item.dart';

/// A candidate memory extracted from conversational text before persistence.
class MemoryCandidate {
  final String content;
  final MemoryCategory category;
  final int importance;
  final String? characterId;
  final String? topicKey;

  const MemoryCandidate({
    required this.content,
    required this.category,
    required this.importance,
    this.characterId,
    this.topicKey,
  });

  bool get isGlobal => characterId == null || characterId!.isEmpty;

  @override
  String toString() =>
      'MemoryCandidate(content: "$content", category: $category, importance: $importance, characterId: $characterId, topicKey: $topicKey)';
}

/// Abstract interface for extracting candidate memories from conversation turns.
/// Decoupled from specific AI providers or extraction techniques.
abstract class MemoryExtractor {
  List<MemoryCandidate> extractCandidates(
    String text, {
    String? activeCharacterId,
    String language = 'en',
  });
}

/// Lightweight, deterministic memory candidate extractor for English and Afrikaans.
///
/// Features:
/// - Zero external AI network calls (fast, cheap, offline-safe).
/// - Detects explicit memory commands ("remember that...", "onthou dat...").
/// - Detects strong preference statements ("I prefer...", "I love...", "Ek hou van...").
/// - Detects persistent personal facts ("My name is...", "I live in...", "Ek werk as...").
/// - Detects skills and workflows ("I code in...", "Ek programmeer in...").
/// - Rejects transient filler, greetings, and temporary questions.
/// - Tags character-specific rapport only when the active persona is directly addressed.
class DeterministicMemoryExtractor implements MemoryExtractor {
  /// Minimum importance required for a candidate to be considered for persistence.
  final int minImportanceThreshold;

  const DeterministicMemoryExtractor({
    this.minImportanceThreshold = 3,
  });

  @override
  List<MemoryCandidate> extractCandidates(
    String text, {
    String? activeCharacterId,
    String language = 'en',
  }) {
    final clean = text.trim();
    if (clean.length < 8) return [];

    // Filter out obvious greetings, questions, or transient filler
    if (_isTransientOrGreeting(clean)) return [];

    final candidates = <MemoryCandidate>[];

    // 1. Explicit memory instructions (Highest priority: Importance 5)
    final explicitMatch = _checkExplicitRemember(clean, activeCharacterId);
    if (explicitMatch != null) {
      candidates.add(explicitMatch);
      return candidates; // Explicit command takes complete precedence
    }

    // 2. Personal Preferences (Importance 3–4)
    final prefMatch = _checkPreferences(clean, activeCharacterId);
    if (prefMatch != null) {
      candidates.add(prefMatch);
    }

    // 3. Factual & Personal Information (Importance 3–4)
    final factMatch = _checkPersonalFacts(clean, activeCharacterId);
    if (factMatch != null) {
      candidates.add(factMatch);
    }

    // 4. Skills & Workflows (Importance 3)
    final skillMatch = _checkSkills(clean, activeCharacterId);
    if (skillMatch != null) {
      candidates.add(skillMatch);
    }

    // 5. Significant Events (Importance 3–4)
    final eventMatch = _checkEvents(clean, activeCharacterId);
    if (eventMatch != null) {
      candidates.add(eventMatch);
    }

    // 6. Character-Specific Relationship & Rapport (Importance 3)
    final relationshipMatch = _checkRelationship(clean, activeCharacterId);
    if (relationshipMatch != null) {
      candidates.add(relationshipMatch);
    }

    // Filter by importance threshold
    return candidates
        .where((c) => c.importance >= minImportanceThreshold)
        .toList();
  }

  /// Returns true if the message is merely a greeting, short acknowledgement, or transient query/status.
  bool _isTransientOrGreeting(String text) {
    final trimmed = text.trim();
    final lower = trimmed.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '');
    final words = lower.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

    if (words.isEmpty) return true;

    // Check if the message is a question without explicit remember commands
    final isExplicitMemoryCommand = lower.contains('remember') || lower.contains('onthou');
    if (trimmed.endsWith('?') && !isExplicitMemoryCommand) {
      return true;
    }

    // Common single-word or short responses / filler
    const fillerWords = {
      'hi', 'hello', 'hey', 'greetings', 'howdy', 'yo',
      'hallo', 'haai', 'goeiemore', 'goeiemiddag', 'goeienaand',
      'ok', 'okay', 'cool', 'sure', 'yes', 'no', 'yep', 'nope',
      'ja', 'nee', 'goed', 'regso', 'dankie', 'thanks', 'thank you',
      'bye', 'goodbye', 'totsiens', 'cheers',
    };

    if (words.length <= 2 && words.every((w) => fillerWords.contains(w))) {
      return true;
    }

    // Temporary conversational status statements (should not be treated as permanent memories)
    const transientStatuses = [
      'i am fine', 'im fine', 'i am good', 'im good', 'i am okay', 'im okay',
      'i am well', 'im well', 'i am tired', 'im tired', 'i feel tired',
      'i am sick', 'im sick', 'i feel sick', 'i am busy', 'im busy',
      'ek is moeg', 'ek voel moeg', 'ek is besig', 'ek is siek', 'ek voel siek',
      'ek is fyn', 'ek is okei', 'dit gaan goed',
    ];
    for (final status in transientStatuses) {
      if (lower == status || lower.startsWith('$status ')) {
        return true;
      }
    }

    // Common transient question and instruction prefixes
    const transientPrefixes = [
      'what is', 'what are', 'who is', 'where is', 'where are', 'when is', 'why is',
      'how do i', 'how does', 'how to', 'how is', 'can you', 'could you', 'would you',
      'is there', 'are there', 'do you', 'did you', 'will you',
      'wat is', 'wat was', 'wie is', 'waar is', 'wanneer is', 'hoekom is',
      'hoe doen ek', 'hoe werk', 'kan jy', 'sou jy', 'wil jy', 'is daar',
      'tell me about', 'vertel my van', 'explain', 'verduidelik',
      'search for', 'soek vir', 'write a', 'skryf \'n', 'give me', 'gee my',
    ];

    for (final prefix in transientPrefixes) {
      if (lower.startsWith(prefix) && !isExplicitMemoryCommand) {
        return true;
      }
    }

    return false;
  }

  /// Explicit command: "Remember that...", "Please remember...", "Onthou dat..."
  MemoryCandidate? _checkExplicitRemember(String text, String? characterId) {
    final patterns = [
      RegExp(r'^(?:please\s+)?remember\s+(?:that\s+)?(.+)', caseSensitive: false),
      RegExp(r'^(?:don\'t|do\s+not)\s+forget\s+(?:that\s+)?(.+)', caseSensitive: false),
      RegExp(r'^(?:asseblief\s+)?onthou\s+(?:dat\s+)?(.+)', caseSensitive: false),
      RegExp(r'^(?:moenie|moet\s+nie)\s+vergeet\s+(?:dat\s+)?(.+)', caseSensitive: false),
      // Trailing explicit instructions: "My name is Chris. Remember that.", "Ek bly in Kaapstad. Onthou dit."
      RegExp(r'^(.+?)(?:[.,;!]|\s+)+(?:please\s+)?remember\s+(?:that|this)?(?:\s+please)?[.!]?$', caseSensitive: false),
      RegExp(r'^(.+?)(?:[.,;!]|\s+)+(?:don\'t|do\s+not)\s+forget\s+(?:that|this)?[.!]?$', caseSensitive: false),
      RegExp(r'^(.+?)(?:[.,;!]|\s+)+(?:asseblief\s+)?onthou\s+(?:dit|dat)?(?:\s+asseblief)?[.!]?$', caseSensitive: false),
      RegExp(r'^(.+?)(?:[.,;!]|\s+)+(?:moenie|moet\s+nie)\s+vergeet\s+(?:dit|dat)?[.!]?$', caseSensitive: false),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(text.trim());
      if (match != null && match.groupCount >= 1) {
        final content = match.group(1)!.trim();
        if (content.length > 3) {
          final isPref = content.toLowerCase().contains('prefer') ||
              content.toLowerCase().contains('verkies') ||
              content.toLowerCase().contains('like') ||
              content.toLowerCase().contains('hou van');

          String? topicKey;
          final cLower = content.toLowerCase();
          if (cLower.contains('name is') || cLower.contains('naam is')) {
            topicKey = 'user_name';
          } else if (cLower.contains('live in') || cLower.contains('bly in') || cLower.contains('woon in')) {
            topicKey = 'residence';
          }

          return MemoryCandidate(
            content: _formatSentence(content),
            category: isPref ? MemoryCategory.preference : MemoryCategory.semantic,
            importance: 5,
            characterId: null, // explicit facts default to global unless relationship-specific
            topicKey: topicKey,
          );
        }
      }
    }
    return null;
  }

  /// Preferences: "I prefer...", "I like...", "I don't like...", "Ek verkies...", "Ek hou van..."
  MemoryCandidate? _checkPreferences(String text, String? characterId) {
    // Check for conversational deictic references (e.g. "I love that!", "I really like this idea")
    final deicticPatterns = [
      RegExp(r'\b(?:i\s+really\s+like|i\s+love|i\s+dislike|i\s+hate|ek\s+hou\s+baie\s+van|ek\s+hou\s+nie\s+van)\s+(that|this|it|that idea|this idea|that response|what you said|dit|daarvan|hierdie|jou antwoord)\b', caseSensitive: false),
    ];
    for (final dp in deicticPatterns) {
      if (dp.hasMatch(text)) return null;
    }

    // Specific favorite item: "my favorite color is blue", "my gunsteling kos is pizza"
    final favMatch = RegExp(r'\b(?:my\s+favorite|my\s+gunsteling)\s+(\w+)\s+(?:is)\s+(.+)', caseSensitive: false).firstMatch(text);
    if (favMatch != null) {
      final itemCategory = favMatch.group(1)!.toLowerCase();
      return MemoryCandidate(
        content: _formatSentence(text),
        category: MemoryCategory.preference,
        importance: 4,
        characterId: null,
        topicKey: 'favorite_$itemCategory',
      );
    }

    final patterns = [
      RegExp(r'\b(?:i\s+prefer|i\s+really\s+prefer)\s+(.+)', caseSensitive: false),
      RegExp(r'\b(?:my\s+preference\s+is)\s+(.+)', caseSensitive: false),
      RegExp(r'\b(?:i\s+really\s+like|i\s+love)\s+(.+)', caseSensitive: false),
      RegExp(r'\b(?:i\s+dislike|i\s+hate|i\s+don\'t\s+like)\s+(.+)', caseSensitive: false),
      RegExp(r'\b(?:ek\s+verkies|ek\s+hou\s+baie\s+van)\s+(.+)', caseSensitive: false),
      RegExp(r'\b(?:ek\s+hou\s+nie\s+van)\s+(.+)', caseSensitive: false),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        String? topicKey;
        final tLower = text.toLowerCase();
        if (tLower.contains('dark mode') || tLower.contains('light mode')) {
          topicKey = 'pref_theme';
        }

        return MemoryCandidate(
          content: _formatSentence(text),
          category: MemoryCategory.preference,
          importance: 4,
          characterId: null,
          topicKey: topicKey,
        );
      }
    }
    return null;
  }

  /// Personal facts: "My name is...", "I live in...", "I work at...", "Ek bly in...", "Ek werk by..."
  MemoryCandidate? _checkPersonalFacts(String text, String? characterId) {
    // 1. Name match: "My name is Chris", "Call me Alex", "My naam is Johan", "Noem my Sarah"
    final namePattern = RegExp(r'\b(?:my\s+name\s+is|call\s+me|my\s+naam\s+is|noem\s+my)\s+([A-Za-z]+)', caseSensitive: false);
    final nameMatch = namePattern.firstMatch(text);
    if (nameMatch != null) {
      return MemoryCandidate(
        content: _formatSentence(text),
        category: MemoryCategory.semantic,
        importance: 5,
        characterId: null,
        topicKey: 'user_name',
      );
    }

    // 2. Residence: "I live in Cape Town", "I moved to London", "Ek woon in Pretoria", "Ek bly in Stellenbosch"
    final residencePattern = RegExp(r'\b(?:i\s+live\s+in|i\s+moved\s+to|i\s+reside\s+in|ek\s+woon\s+in|ek\s+bly\s+in)\s+(.+)', caseSensitive: false);
    if (residencePattern.hasMatch(text)) {
      return MemoryCandidate(
        content: _formatSentence(text),
        category: MemoryCategory.semantic,
        importance: 4,
        characterId: null,
        topicKey: 'residence',
      );
    }

    // 3. Occupation: "I work at...", "I work as...", "My job is...", "Ek werk by...", "Ek werk as..."
    final workPattern = RegExp(r'\b(?:i\s+work\s+at|i\s+work\s+for|i\s+work\s+as|my\s+job\s+is|ek\s+werk\s+by|ek\s+werk\s+vir|ek\s+werk\s+as|my\s+werk\s+is)\s+(.+)', caseSensitive: false);
    if (workPattern.hasMatch(text)) {
      return MemoryCandidate(
        content: _formatSentence(text),
        category: MemoryCategory.semantic,
        importance: 4,
        characterId: null,
        topicKey: 'occupation',
      );
    }

    // 4. Family & pets
    final familyPattern = RegExp(r'\b(?:my\s+wife|my\s+husband|my\s+partner|my\s+son|my\s+daughter|my\s+dog|my\s+cat|my\s+vrou|my\s+man|my\s+seun|my\s+dogter|my\s+hond|my\s+kat)\b', caseSensitive: false);
    if (familyPattern.hasMatch(text)) {
      String? topicKey;
      final tLower = text.toLowerCase();
      if (tLower.contains('dog') || tLower.contains('hond')) {
        topicKey = 'pet_dog';
      } else if (tLower.contains('cat') || tLower.contains('kat')) {
        topicKey = 'pet_cat';
      }

      return MemoryCandidate(
        content: _formatSentence(text),
        category: MemoryCategory.semantic,
        importance: 4,
        characterId: null,
        topicKey: topicKey,
      );
    }

    return null;
  }

  /// Skills & domain proficiencies
  MemoryCandidate? _checkSkills(String text, String? characterId) {
    final patterns = [
      RegExp(r'\b(?:i\s+code\s+in|i\s+program\s+in|i\s+develop\s+with|my\s+tech\s+stack)\s+(.+)', caseSensitive: false),
      RegExp(r'\b(?:i\s+am\s+learning|i\'m\s+studying)\s+(.+)', caseSensitive: false),
      RegExp(r'\b(?:ek\s+programmeer\s+in|ek\s+leer\s+tans|ek\s+studeer)\s+(.+)', caseSensitive: false),
    ];

    for (final pattern in patterns) {
      if (pattern.hasMatch(text)) {
        return MemoryCandidate(
          content: _formatSentence(text),
          category: MemoryCategory.skill,
          importance: 3,
          characterId: null,
          topicKey: 'skill',
        );
      }
    }
    return null;
  }

  /// Important episodic life events
  MemoryCandidate? _checkEvents(String text, String? characterId) {
    final patterns = [
      RegExp(r'\b(?:i\s+just\s+got\s+a\s+new|i\s+graduated|i\s+started\s+a\s+new|i\s+bought\s+a)\s+(.+)', caseSensitive: false),
      RegExp(r'\b(?:ek\s+het\s+pas\s+\'n\s+nuwe|ek\s+het\s+gegradueer|ek\s+begin\s+\'n\s+nuwe)\s+(.+)', caseSensitive: false),
    ];

    for (final pattern in patterns) {
      if (pattern.hasMatch(text)) {
        return MemoryCandidate(
          content: _formatSentence(text),
          category: MemoryCategory.episodic,
          importance: 3,
          characterId: null,
          topicKey: 'event',
        );
      }
    }
    return null;
  }

  /// Relationship & rapport statements tied to a specific character
  MemoryCandidate? _checkRelationship(String text, String? characterId) {
    if (characterId == null || characterId.isEmpty) return null;

    final patterns = [
      RegExp(r'\b(?:you\s+and\s+i|we\s+always|i\s+trust\s+you|i\s+appreciate\s+talking\s+to\s+you)\b', caseSensitive: false),
      RegExp(r'\b(?:jy\s+en\s+ek|ons\s+twee|ek\s+vertrou\s+jou|ek\s+waardeer\s+ons\s+gesprekke)\b', caseSensitive: false),
    ];

    for (final pattern in patterns) {
      if (pattern.hasMatch(text)) {
        return MemoryCandidate(
          content: _formatSentence(text),
          category: MemoryCategory.relationship,
          importance: 3,
          characterId: characterId,
          topicKey: 'relationship_$characterId',
        );
      }
    }
    return null;
  }

  String _formatSentence(String str) {
    final trimmed = str.trim();
    if (trimmed.isEmpty) return trimmed;
    final firstUpper = trimmed[0].toUpperCase() + trimmed.substring(1);
    if (!firstUpper.endsWith('.') && !firstUpper.endsWith('!') && !firstUpper.endsWith('?')) {
      return '$firstUpper.';
    }
    return firstUpper;
  }
}
