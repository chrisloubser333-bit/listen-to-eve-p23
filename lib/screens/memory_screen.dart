import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/memory_item.dart';
import '../providers/settings_provider.dart';
import '../services/memory_service.dart';
import '../theme/app_theme.dart';
import 'settings_screen.dart';

class MemoryScreen extends StatefulWidget {
  const MemoryScreen({super.key});

  @override
  State<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends State<MemoryScreen> {
  String _filter = 'all';

  Color _categoryColor(MemoryCategory cat) {
    switch (cat) {
      case MemoryCategory.semantic:
        return AppTheme.primary; // Cyan
      case MemoryCategory.preference:
        return AppTheme.secondary; // Purple
      case MemoryCategory.episodic:
        return AppTheme.accent; // Amber
      case MemoryCategory.relationship:
        return const Color(0xFFFF6584); // Rose
      case MemoryCategory.skill:
        return AppTheme.success; // Emerald
    }
  }

  IconData _categoryIcon(MemoryCategory cat) {
    switch (cat) {
      case MemoryCategory.semantic:
        return Icons.psychology_rounded;
      case MemoryCategory.preference:
        return Icons.tune_rounded;
      case MemoryCategory.episodic:
        return Icons.event_note_rounded;
      case MemoryCategory.relationship:
        return Icons.favorite_rounded;
      case MemoryCategory.skill:
        return Icons.auto_awesome_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final memoryService = context.watch<MemoryService>();
    final isAf = settings.language == 'af';

    final filtered = _filter == 'all'
        ? memoryService.memories
        : memoryService.getMemoriesByCategory(MemoryCategory.fromString(_filter));

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(isAf ? 'Geheue' : 'Memory'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded, color: AppTheme.primary),
            tooltip: isAf ? 'Voeg herinnering by' : 'Add memory',
            onPressed: () => _showAddMemory(context, memoryService, isAf),
          ),
        ],
      ),
      body: memoryService.isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                // Core Profile card
                _sectionTitle(isAf ? 'Kernprofiel' : 'Core Profile'),
                _glassCard(
                  borderColor: AppTheme.secondary.withOpacity(0.4),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.person_rounded,
                              color: AppTheme.secondary,
                              size: 22,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              isAf ? 'Oor jou' : 'About you',
                              style: const TextStyle(
                                color: AppTheme.textPrimary,
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _profileLine(
                          isAf
                              ? 'Taal: ${settings.language == 'af' ? 'Afrikaans' : 'Engels'}'
                              : 'Language: ${settings.language == 'af' ? 'Afrikaans' : 'English'}',
                        ),
                        _profileLine(
                          isAf
                              ? 'Aktiewe karakter: ${settings.activeCharacter.name}'
                              : 'Active character: ${settings.activeCharacter.name}',
                        ),
                        _profileLine(
                          isAf
                              ? 'Aktiewe stem: ${settings.voiceId.toUpperCase()}'
                              : 'Active voice: ${settings.voiceId.toUpperCase()}',
                        ),
                        _profileLine(
                          isAf
                              ? '${memoryService.memories.length} herinneringe gestoor'
                              : '${memoryService.memories.length} memories stored',
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            icon: const Icon(Icons.settings_rounded, size: 16),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const SettingsScreen(),
                                ),
                              );
                            },
                            label: Text(isAf ? 'Instellings' : 'Settings'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Filter chips
                _sectionTitle(isAf ? 'Herinneringe' : 'Memories'),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _filterChip('all', isAf ? 'Alles' : 'All'),
                      _filterChip('semantic', isAf ? 'Semanties' : 'Semantic'),
                      _filterChip('preference', isAf ? 'Voorkeure' : 'Preferences'),
                      _filterChip('episodic', isAf ? 'Episodies' : 'Episodic'),
                      _filterChip('relationship', isAf ? 'Verhouding' : 'Relationship'),
                      _filterChip('skill', isAf ? 'Vaardighede' : 'Skills'),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Memory list
                if (filtered.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Column(
                      children: [
                        Icon(
                          Icons.psychology_outlined,
                          size: 56,
                          color: AppTheme.textSecondary.withOpacity(0.5),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          isAf
                              ? 'Nog geen herinneringe in hierdie kategorie nie'
                              : 'No memories in this category yet',
                          style: const TextStyle(color: AppTheme.textSecondary),
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.add_rounded, size: 18),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.primary,
                            side: const BorderSide(color: AppTheme.primary),
                          ),
                          onPressed: () => _showAddMemory(context, memoryService, isAf),
                          label: Text(
                            isAf ? 'Voeg herinnering by' : 'Add memory',
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  ...filtered.map((m) => _memoryTile(m, memoryService, isAf)),

                const SizedBox(height: 28),

                // Privacy / management
                _sectionTitle(isAf ? 'Privaatheid' : 'Privacy'),
                _glassCard(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(
                          Icons.delete_forever_rounded,
                          color: Color(0xFFFF6B6B),
                        ),
                        title: Text(
                          isAf ? 'Vee alle herinneringe uit' : 'Delete all memories',
                          style: const TextStyle(color: Color(0xFFFF6B6B)),
                        ),
                        onTap: () => _confirmDeleteAll(context, memoryService, isAf),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: const TextStyle(
          color: AppTheme.textPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _glassCard({required Widget child, Color? borderColor}) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: borderColor ?? AppTheme.border.withOpacity(0.6),
        ),
      ),
      child: child,
    );
  }

  Widget _profileLine(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: const BoxDecoration(
              color: AppTheme.secondary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String value, String label) {
    final selected = _filter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => setState(() => _filter = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.primary.withOpacity(0.18)
                : AppTheme.surface.withOpacity(0.6),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? AppTheme.primary.withOpacity(0.7)
                  : AppTheme.border.withOpacity(0.5),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? AppTheme.primary : AppTheme.textSecondary,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  Widget _memoryTile(MemoryItem m, MemoryService memoryService, bool isAf) {
    final color = _categoryColor(m.category);
    final importanceStars = '★' * m.importance;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _glassCard(
        borderColor: color.withOpacity(0.35),
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(_categoryIcon(m.category), color: color, size: 20),
          ),
          title: Text(
            m.content,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 14,
              height: 1.3,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '${m.category.displayNameAf(isAf).toUpperCase()} · ${_timeAgo(m.createdAt, isAf)} · $importanceStars',
              style: TextStyle(
                color: color.withOpacity(0.9),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          trailing: IconButton(
            icon: const Icon(Icons.more_horiz_rounded,
                color: AppTheme.textSecondary),
            onPressed: () => _showMemoryActions(m, memoryService, isAf),
          ),
          onTap: () => _showMemoryActions(m, memoryService, isAf),
        ),
      ),
    );
  }

  String _timeAgo(DateTime dt, bool isAf) {
    final diff = DateTime.now().difference(dt);
    if (diff.inDays > 1) {
      return isAf ? '${diff.inDays} dae gelede' : '${diff.inDays} days ago';
    }
    if (diff.inDays == 1) return isAf ? '1 dag gelede' : '1 day ago';
    if (diff.inHours >= 1) {
      return isAf ? '${diff.inHours} ure gelede' : '${diff.inHours} hours ago';
    }
    return isAf ? 'Pas nou' : 'Just now';
  }

  void _showMemoryActions(MemoryItem m, MemoryService memoryService, bool isAf) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  m.content,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 20),
                ListTile(
                  leading: const Icon(Icons.edit_rounded,
                      color: AppTheme.primary),
                  title: Text(isAf ? 'Wysig' : 'Edit',
                      style: const TextStyle(color: AppTheme.textPrimary)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showEditMemory(m, memoryService, isAf);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete_rounded,
                      color: Color(0xFFFF6B6B)),
                  title: Text(isAf ? 'Vee uit' : 'Delete',
                      style: const TextStyle(color: Color(0xFFFF6B6B))),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await memoryService.deleteMemory(m.id);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showAddMemory(BuildContext ctx, MemoryService memoryService, bool isAf) {
    final controller = TextEditingController();
    final charName = ctx.read<SettingsProvider>().activeCharacter.name;
    MemoryCategory selectedCategory = MemoryCategory.semantic;
    int selectedImportance = 3;

    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (modalCtx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    isAf ? 'Voeg herinnering by' : 'Add memory',
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    maxLines: 3,
                    style: const TextStyle(color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      hintText: isAf
                          ? 'Wat moet $charName onthou?'
                          : 'What should $charName remember?',
                      hintStyle: const TextStyle(color: AppTheme.textSecondary),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    isAf ? 'Kategorie' : 'Category',
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: MemoryCategory.values.map((cat) {
                      final isSelected = selectedCategory == cat;
                      return ChoiceChip(
                        label: Text(cat.displayNameAf(isAf)),
                        selected: isSelected,
                        onSelected: (_) {
                          setModalState(() => selectedCategory = cat);
                        },
                        selectedColor: _categoryColor(cat).withOpacity(0.25),
                        labelStyle: TextStyle(
                          color: isSelected
                              ? _categoryColor(cat)
                              : AppTheme.textSecondary,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        isAf ? 'Belangrikheid' : 'Importance',
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Row(
                        children: List.generate(5, (index) {
                          final starIndex = index + 1;
                          final isFilled = starIndex <= selectedImportance;
                          return IconButton(
                            iconSize: 22,
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            constraints: const BoxConstraints(),
                            icon: Icon(
                              isFilled ? Icons.star_rounded : Icons.star_border_rounded,
                              color: isFilled ? AppTheme.accent : AppTheme.textSecondary,
                            ),
                            onPressed: () {
                              setModalState(() => selectedImportance = starIndex);
                            },
                          );
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () async {
                      final text = controller.text.trim();
                      if (text.isEmpty) return;
                      Navigator.pop(modalCtx);
                      await memoryService.addMemory(
                        content: text,
                        category: selectedCategory,
                        importance: selectedImportance,
                      );
                    },
                    child: Text(isAf ? 'Stoor' : 'Save'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showEditMemory(MemoryItem m, MemoryService memoryService, bool isAf) {
    final controller = TextEditingController(text: m.content);
    final charName = context.read<SettingsProvider>().activeCharacter.name;
    MemoryCategory selectedCategory = m.category;
    int selectedImportance = m.importance;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (modalCtx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    isAf ? 'Wysig herinnering' : 'Edit memory',
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    maxLines: 3,
                    style: const TextStyle(color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      hintText: isAf
                          ? 'Wat moet $charName onthou?'
                          : 'What should $charName remember?',
                      hintStyle: const TextStyle(color: AppTheme.textSecondary),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    isAf ? 'Kategorie' : 'Category',
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: MemoryCategory.values.map((cat) {
                      final isSelected = selectedCategory == cat;
                      return ChoiceChip(
                        label: Text(cat.displayNameAf(isAf)),
                        selected: isSelected,
                        onSelected: (_) {
                          setModalState(() => selectedCategory = cat);
                        },
                        selectedColor: _categoryColor(cat).withOpacity(0.25),
                        labelStyle: TextStyle(
                          color: isSelected
                              ? _categoryColor(cat)
                              : AppTheme.textSecondary,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        isAf ? 'Belangrikheid' : 'Importance',
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Row(
                        children: List.generate(5, (index) {
                          final starIndex = index + 1;
                          final isFilled = starIndex <= selectedImportance;
                          return IconButton(
                            iconSize: 22,
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            constraints: const BoxConstraints(),
                            icon: Icon(
                              isFilled ? Icons.star_rounded : Icons.star_border_rounded,
                              color: isFilled ? AppTheme.accent : AppTheme.textSecondary,
                            ),
                            onPressed: () {
                              setModalState(() => selectedImportance = starIndex);
                            },
                          );
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () async {
                      final text = controller.text.trim();
                      if (text.isEmpty) return;
                      Navigator.pop(modalCtx);
                      await memoryService.updateMemory(
                        m.copyWith(
                          content: text,
                          category: selectedCategory,
                          importance: selectedImportance,
                        ),
                      );
                    },
                    child: Text(isAf ? 'Stoor' : 'Save'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _confirmDeleteAll(
    BuildContext ctx,
    MemoryService memoryService,
    bool isAf,
  ) {
    showDialog(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(
          isAf ? 'Vee alles uit?' : 'Delete everything?',
          style: const TextStyle(color: AppTheme.textPrimary),
        ),
        content: Text(
          isAf
              ? 'Alle herinneringe sal permanent verwyder word.'
              : 'All memories will be permanently removed.',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text(isAf ? 'Kanselleer' : 'Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFF6B6B),
            ),
            onPressed: () async {
              Navigator.pop(dialogCtx);
              await memoryService.clearAllMemories();
            },
            child: Text(isAf ? 'Vee uit' : 'Delete'),
          ),
        ],
      ),
    );
  }
}
