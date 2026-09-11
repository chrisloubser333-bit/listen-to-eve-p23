import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/memory_item.dart';
import 'memory_extractor.dart';
import 'storage_service.dart';

/// Service responsible for managing, persisting, and retrieving user memories.
///
/// Follows AGENTS.md Rule 6:
/// - Maintains persistent storage independent of any AI model provider
/// - Supports semantic, preference, episodic, relationship, and skill categories
/// - Tracks importance, access counts, and timestamps for future decay/reinforcement
class MemoryService extends ChangeNotifier {
  final StorageService _storage;
  final MemoryExtractor _defaultExtractor;
  final _uuid = const Uuid();

  List<MemoryItem> _memories = [];
  bool _isLoading = false;
  Future<void>? _initFuture;

  MemoryService(
    this._storage, {
    MemoryExtractor? extractor,
  })  : _defaultExtractor = extractor ?? const DeterministicMemoryExtractor(minImportanceThreshold: 3) {
    _initFuture = loadMemories();
  }

  /// Ensures that initial memory loading from storage has completed.
  Future<void> ensureInitialized() async {
    if (_initFuture != null) {
      await _initFuture;
    }
  }

  /// Extractor used for conversational candidate detection.
  MemoryExtractor get extractor => _defaultExtractor;

  /// All stored memories, ordered by importance (descending), then creation date (descending).
  List<MemoryItem> get memories => List.unmodifiable(_memories);

  /// Whether memories are currently being loaded from storage.
  bool get isLoading => _isLoading;

  /// Loads all memories from persistent storage.
  Future<void> loadMemories() async {
    _isLoading = true;
    notifyListeners();

    try {
      _memories = await _storage.loadMemories();
      _sortMemories();
    } catch (e) {
      debugPrint('MemoryService loadMemories error: $e');
      _memories = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Saves the current list of memories to persistent storage.
  Future<void> saveMemories() async {
    try {
      await _storage.saveMemories(_memories);
    } catch (e) {
      debugPrint('MemoryService saveMemories error: $e');
    }
  }

  /// Adds a new memory item and persists it.
  Future<MemoryItem> addMemory({
    required String content,
    required MemoryCategory category,
    int importance = 3,
    String? characterId,
    String? topicKey,
  }) async {
    if (_initFuture != null) await _initFuture;

    final now = DateTime.now();
    final item = MemoryItem(
      id: _uuid.v4(),
      content: content.trim(),
      category: category,
      importance: importance.clamp(1, 5),
      createdAt: now,
      updatedAt: now,
      lastAccessedAt: null,
      accessCount: 0,
      characterId: characterId,
      topicKey: topicKey,
    );

    _memories.insert(0, item);
    _sortMemories();
    await saveMemories();
    notifyListeners();
    return item;
  }

  /// Updates an existing memory item and persists the changes.
  Future<void> updateMemory(MemoryItem updated) async {
    final idx = _memories.indexWhere((m) => m.id == updated.id);
    if (idx != -1) {
      _memories[idx] = updated.copyWith(updatedAt: DateTime.now());
      _sortMemories();
      await saveMemories();
      notifyListeners();
    }
  }

  /// Deletes a memory item by ID and persists the removal.
  Future<void> deleteMemory(String id) async {
    _memories.removeWhere((m) => m.id == id);
    await saveMemories();
    notifyListeners();
  }

  /// Clears all memories from memory and storage.
  Future<void> clearAllMemories() async {
    _memories.clear();
    await _storage.clearMemories();
    notifyListeners();
  }

  /// Filters memories by category.
  List<MemoryItem> getMemoriesByCategory(MemoryCategory? category) {
    if (category == null) return memories;
    return _memories.where((m) => m.category == category).toList();
  }

  /// Returns memories accessible to a specific character:
  /// - If [characterId] is null or empty, returns only global memories (isGlobal).
  /// - If [characterId] is provided, returns global memories AND memories specific to that character.
  /// Character-specific relationship memories never leak between different characters.
  List<MemoryItem> getMemoriesForCharacter(String? characterId) {
    if (characterId == null || characterId.isEmpty) {
      return _memories.where((m) => m.isGlobal).toList();
    }
    return _memories
        .where((m) => m.isGlobal || m.characterId == characterId)
        .toList();
  }

  /// Searches memories by text content, optional category, and optional character isolation.
  List<MemoryItem> searchMemories(
    String query, {
    MemoryCategory? category,
    String? characterId,
  }) {
    final trimmed = query.trim().toLowerCase();
    return _memories.where((m) {
      final matchesCategory = category == null || m.category == category;
      final matchesCharacter = characterId == null ||
          characterId.isEmpty ||
          m.isGlobal ||
          m.characterId == characterId;
      final matchesQuery = trimmed.isEmpty || m.content.toLowerCase().contains(trimmed);
      return matchesCategory && matchesCharacter && matchesQuery;
    }).toList();
  }

  /// Checks whether an existing memory accessible to [characterId] is substantially
  /// identical, shares the same topic key, or overlaps significantly with [content].
  MemoryItem? findSimilarMemory(
    String content, {
    String? characterId,
    MemoryCategory? category,
    String? topicKey,
  }) {
    final candidates = getMemoriesForCharacter(characterId);
    if (candidates.isEmpty) return null;

    // 1. Explicit topicKey match (e.g. 'residence', 'user_name', 'favorite_color')
    if (topicKey != null && topicKey.isNotEmpty) {
      for (final memory in candidates) {
        if (memory.topicKey == topicKey) {
          return memory;
        }
      }
    }

    final clean = content.trim().toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '');
    if (clean.isEmpty) return null;

    // 2. Exact normalized string match
    for (final memory in candidates) {
      if (category != null && memory.category != category) continue;
      final memClean = memory.content.trim().toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '');
      if (clean == memClean) return memory;
    }

    // 3. Shared key-prefix match (e.g. "my name is", "i live in", "ek bly in", "my favorite")
    const commonPrefixes = [
      'my name is', 'call me', 'my naam is', 'noem my',
      'i live in', 'i moved to', 'ek woon in', 'ek bly in',
      'my favorite', 'my gunsteling',
      'i work at', 'i work as', 'ek werk by', 'ek werk as',
    ];
    for (final prefix in commonPrefixes) {
      if (clean.startsWith(prefix)) {
        for (final memory in candidates) {
          final memClean = memory.content.trim().toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '');
          if (memClean.startsWith(prefix)) {
            return memory;
          }
        }
      }
    }

    // 4. Token overlap analysis (Jaccard and subset overlap)
    final tokens = clean.split(RegExp(r'\s+')).where((t) => t.length > 2).toSet();
    if (tokens.isEmpty) return null;

    for (final memory in candidates) {
      if (category != null && memory.category != category) continue;

      final memClean = memory.content.trim().toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '');
      final memTokens = memClean.split(RegExp(r'\s+')).where((t) => t.length > 2).toSet();
      if (memTokens.isEmpty) continue;

      final intersection = tokens.intersection(memTokens).length;
      final union = tokens.union(memTokens).length;
      final jaccard = union > 0 ? intersection / union : 0.0;

      // Substantially similar if high Jaccard overlap (>= 0.65)
      if (jaccard >= 0.65) {
        return memory;
      }

      // Check subset overlap
      final smallerLen = tokens.length < memTokens.length ? tokens.length : memTokens.length;
      final overlapRatio = intersection / smallerLen;
      if (intersection >= 3 && overlapRatio >= 0.85) {
        return memory;
      }
    }
    return null;
  }

  /// Ingests a candidate memory. Applies deduplication & reinforcement:
  /// - If similar memory exists on the same topic: reinforces it (accessCount++, updates lastAccessedAt),
  ///   promotes importance if candidate is higher, and updates content if the candidate provides
  ///   richer detail or an updated fact on the same topic (resolving contradictions).
  /// - If new: persists a new memory item.
  Future<MemoryItem> ingestCandidate(MemoryCandidate candidate) async {
    if (_initFuture != null) await _initFuture;

    final existing = findSimilarMemory(
      candidate.content,
      characterId: candidate.characterId,
      category: candidate.category,
      topicKey: candidate.topicKey,
    );

    if (existing != null) {
      final now = DateTime.now();
      final newImportance = candidate.importance > existing.importance
          ? candidate.importance
          : existing.importance;

      // Check if candidate is an updated fact on the same topic or provides richer detail
      final isSameTopic = candidate.topicKey != null && candidate.topicKey == existing.topicKey;
      final isContentDifferent = candidate.content.trim().toLowerCase() != existing.content.trim().toLowerCase();
      final isRicherContent = candidate.content.trim().length > existing.content.trim().length + 8;

      final shouldUpdateContent = (isSameTopic && isContentDifferent) || isRicherContent;
      final newContent = shouldUpdateContent ? candidate.content.trim() : existing.content;

      final reinforced = existing.copyWith(
        content: newContent,
        importance: newImportance,
        accessCount: existing.accessCount + 1,
        lastAccessedAt: now,
        updatedAt: shouldUpdateContent ? now : existing.updatedAt,
        topicKey: candidate.topicKey ?? existing.topicKey,
      );

      final idx = _memories.indexWhere((m) => m.id == existing.id);
      if (idx != -1) {
        _memories[idx] = reinforced;
        _sortMemories();
        await saveMemories();
        notifyListeners();
      }
      return reinforced;
    } else {
      return await addMemory(
        content: candidate.content,
        category: candidate.category,
        importance: candidate.importance,
        characterId: candidate.characterId,
        topicKey: candidate.topicKey,
      );
    }
  }

  /// Evaluates a user message, extracts memory candidates using [extractor],
  /// and persists or reinforces high-value memories without any external AI call.
  Future<List<MemoryItem>> processUserMessage(
    String text, {
    required String characterId,
    String language = 'en',
    MemoryExtractor? extractor,
  }) async {
    if (_initFuture != null) await _initFuture;

    final ext = extractor ?? _defaultExtractor;
    final candidates = ext.extractCandidates(
      text,
      activeCharacterId: characterId,
      language: language,
    );

    if (candidates.isEmpty) return [];

    final processed = <MemoryItem>[];
    for (final candidate in candidates) {
      final item = await ingestCandidate(candidate);
      processed.add(item);
    }
    return processed;
  }

  /// Retrieves the most relevant memories for a prompt/query considering:
  /// - Query text token overlap & stem matching (excluding false positive substring matches)
  /// - Character partition (character-specific memories do not leak across personas)
  /// - Importance (1–5 scale)
  /// - Category context
  /// - Recency & access count reinforcement
  ///
  /// Automatically reinforces retrieved memories ([lastAccessedAt] and [accessCount]),
  /// with a 60-second cooldown to avoid redundant disk writes in rapid conversational bursts.
  Future<List<MemoryItem>> retrieveRelevantMemories(
    String query, {
    int limit = 4,
    String? characterId,
    MemoryCategory? preferredCategory,
  }) async {
    if (_initFuture != null) await _initFuture;
    if (query.trim().isEmpty || _memories.isEmpty) return [];

    // Filter by character accessibility (character-specific memories must not leak to other characters)
    final candidatePool = getMemoriesForCharacter(characterId);
    if (candidatePool.isEmpty) return [];

    // Stop words to ignore during query tokenization (English and Afrikaans)
    const stopWords = {
      // English articles, prepositions, conjunctions
      'the', 'is', 'are', 'was', 'were', 'be', 'been', 'being',
      'at', 'which', 'on', 'a', 'an', 'and', 'or', 'in', 'to',
      'for', 'of', 'with', 'about', 'as', 'by', 'that', 'this', 'it', 'from',
      // English pronouns
      'i', 'me', 'my', 'myself', 'we', 'our', 'ours', 'ourselves',
      'you', 'your', 'yours', 'yourself', 'yourselves',
      'he', 'him', 'his', 'himself', 'she', 'her', 'hers', 'herself',
      'they', 'them', 'their', 'theirs', 'themselves',
      // English auxiliary verbs & modals
      'have', 'has', 'had', 'having', 'do', 'does', 'did', 'doing',
      'would', 'should', 'could', 'ought', 'can', 'will', 'shall', 'may', 'might', 'must',
      // English question words & adverbs
      'what', 'which', 'who', 'whom', 'how', 'when', 'where', 'why',
      // English greetings & conversational filler
      'hello', 'hi', 'hey', 'good', 'morning', 'afternoon', 'evening', 'night', 'day', 'today',
      'thanks', 'thank', 'please', 'okay', 'yes', 'no', 'just', 'so', 'too', 'very',
      // Character names (prevent character name query match)
      'eve', 'ara', 'leo', 'rex', 'sal',
      // Afrikaans articles, prepositions, conjunctions
      'die', 'at', 'by', 'wat', 'op', '\'n', 'en', 'of', 'in', 'na',
      'vir', 'van', 'met', 'oor', 'as', 'deur', 'dat', 'hierdie', 'dit', 'daardie',
      // Afrikaans pronouns
      'ek', 'my', 'myne', 'myself', 'ons', 'onsne', 'onslewe',
      'jy', 'jou', 'joune', 'jouself', 'julle',
      'hy', 'hom', 'sy', 'syne', 'synde', 'haar', 'hare',
      'hulle', 'hul', 'hulse',
      // Afrikaans verbs & modals
      'is', 'was', 'wees', 'word', 'gewees', 'het', 'he', 'kan', 'kon',
      'sal', 'sou', 'moet', 'moes', 'mag', 'gaan',
      // Afrikaans question words & adverbs
      'wat', 'wie', 'waar', 'wanneer', 'hoekom', 'waarom', 'hoe',
      // Afrikaans greetings & filler
      'hallo', 'haai', 'goeie', 'more', 'môre', 'middag', 'aand', 'dag', 'vandag',
      'dankie', 'asseblief', 'goed', 'regso', 'ja', 'nee', 'nie', 'net', 'baie', 'ook', 'maar',
    };

    final queryClean = query.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), ' ');
    final tokens = queryClean
        .split(RegExp(r'\s+'))
        .where((t) => t.length > 2 && !stopWords.contains(t))
        .toSet();

    final isIdentityQuery = queryClean.contains('who am i') ||
        queryClean.contains('what is my name') ||
        queryClean.contains('whats my name') ||
        queryClean.contains('wie is ek') ||
        queryClean.contains('wat is my naam');

    if (tokens.isEmpty && !isIdentityQuery) return [];

    final scored = <MapEntry<MemoryItem, int>>[];
    final now = DateTime.now();

    for (final memory in candidatePool) {
      int queryScore = 0;
      final memLower = memory.content.toLowerCase();
      final memTokens = memLower
          .replaceAll(RegExp(r'[^\w\s]'), ' ')
          .split(RegExp(r'\s+'))
          .where((t) => t.length > 2)
          .toSet();

      // Identity query match
      if (isIdentityQuery &&
          (memory.topicKey == 'user_name' ||
              memLower.contains('name is') ||
              memLower.contains('naam is'))) {
        queryScore += 30;
      }

      // Token overlap with boundary checks (no spurious substring matches inside unrelated words)
      for (final token in tokens) {
        if (memTokens.contains(token)) {
          queryScore += 15; // exact token match
        } else if (token.length >= 4) {
          // Stem/prefix match for inflected words (e.g. 'program' and 'programming')
          final hasStemMatch = memTokens.any(
            (mt) => mt.startsWith(token) || token.startsWith(mt),
          );
          if (hasStemMatch) {
            queryScore += 8;
          }
        }
      }

      // Check for multi-word phrase overlap
      if (tokens.length >= 2) {
        final phrase = tokens.take(3).join(' ');
        if (memLower.contains(phrase)) {
          queryScore += 20;
        }
      }

      // Only consider memories that have genuine relevance to the query (queryScore >= 8)
      if (queryScore >= 8) {
        int totalScore = queryScore;

        // Importance weight (1..5 scale gives 3..15 points)
        totalScore += memory.importance * 3;

        // Category preference
        if (preferredCategory != null && memory.category == preferredCategory) {
          totalScore += 8;
        } else if (memory.category == MemoryCategory.preference) {
          totalScore += 5; // General preference bonus
        }

        // Access/reinforcement bonus (frequently recalled memories)
        if (memory.accessCount > 0) {
          totalScore += (memory.accessCount * 2).clamp(0, 10);
        }

        // Recency bonus (memories accessed or created recently)
        final lastTime = memory.lastAccessedAt ?? memory.createdAt;
        final daysSince = now.difference(lastTime).inDays;
        if (daysSince <= 2) {
          totalScore += 6;
        } else if (daysSince <= 7) {
          totalScore += 4;
        } else if (daysSince <= 30) {
          totalScore += 2;
        }

        scored.add(MapEntry(memory, totalScore));
      }
    }

    if (scored.isEmpty) return [];

    scored.sort((a, b) => b.value.compareTo(a.value));
    final relevant = scored.take(limit).map((e) => e.key).toList();

    if (relevant.isNotEmpty) {
      // Reinforce retrieved memories with cooldown to prevent rapid repetitive disk writes
      bool changed = false;
      for (int i = 0; i < _memories.length; i++) {
        if (relevant.any((r) => r.id == _memories[i].id)) {
          final mem = _memories[i];
          final lastTime = mem.lastAccessedAt;
          // 60-second cooldown per memory item
          final shouldReinforce = lastTime == null || now.difference(lastTime).inSeconds >= 60;

          if (shouldReinforce) {
            _memories[i] = mem.copyWith(
              lastAccessedAt: now,
              accessCount: mem.accessCount + 1,
            );
            changed = true;
          }
        }
      }
      if (changed) {
        await saveMemories();
        notifyListeners();
      }
    }

    return relevant;
  }

  void _sortMemories() {
    _memories.sort((a, b) {
      final cmp = b.importance.compareTo(a.importance);
      if (cmp != 0) return cmp;
      return b.createdAt.compareTo(a.createdAt);
    });
  }
}
