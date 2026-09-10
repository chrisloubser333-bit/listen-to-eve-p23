import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../providers/settings_provider.dart';
import '../models/character_profile.dart';
import '../models/message.dart';
import 'settings_screen.dart';
import '../widgets/message_bubble.dart';
import '../widgets/voice_button.dart';
import '../theme/app_theme.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  int _lastMessageCount = 0;
  bool _bannerDismissed = false;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    final chat = context.read<ChatProvider>();
    await chat.sendText(text);
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final settings = context.watch<SettingsProvider>();
    final character = settings.activeCharacter;
    final isAf = settings.language == 'af';
    final theme = Theme.of(context);

    // Only scroll when message count changes (event-driven, never on continuous rebuilds)
    if (chat.messages.length != _lastMessageCount) {
      _lastMessageCount = chat.messages.length;
      _scrollToBottom();
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppTheme.primary.withOpacity(0.8),
                  width: 1.5,
                ),
                boxShadow: AppTheme.glow(AppTheme.primary, blur: 10, spread: 0),
              ),
              child: ClipOval(
                child: Image.asset(
                  character.avatarAsset,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Icon(
                    character.icon,
                    size: 20,
                    color: AppTheme.primary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    character.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                      letterSpacing: 0.2,
                    ),
                  ),
                  Text(
                    '${isAf ? "Afrikaans" : "English"} • ${character.getTagline(isAf)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppTheme.textSecondary,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: AppTheme.textPrimary),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Character quick-switch pill selector (Preserves character identity independently)
            _buildCharacterBar(settings),

            // Optional non-blocking API tip banner
            if (!chat.hasApiKey && !_bannerDismissed)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceLight.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.primary.withOpacity(0.25),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.auto_awesome, size: 16, color: AppTheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        isAf
                            ? 'Aktiewe klets aanlyn. Voeg opsionele API-sleutel by in Instellings.'
                            : 'Active chat online. You can add a custom API key anytime in Settings.',
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 16, color: AppTheme.textSecondary),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => setState(() => _bannerDismissed = true),
                    ),
                  ],
                ),
              ),

            // Error banner
            if (chat.error != null)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.withOpacity(0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        chat.error!,
                        style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton(
                      onPressed: () => chat.clearError(),
                      child: Text(isAf ? 'Sluit' : 'Dismiss', style: const TextStyle(color: Colors.redAccent)),
                    ),
                  ],
                ),
              ),

            // Main chat or adaptive hero presentation
            Expanded(
              child: chat.messages.isEmpty
                  ? _buildAdaptiveHeroEmptyState(context, settings, character, isAf)
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      itemCount: chat.messages.length,
                      itemBuilder: (context, index) {
                        final msg = chat.messages[index];
                        return MessageBubble(
                          message: msg,
                          avatarAsset: msg.role == MessageRole.assistant
                              ? character.avatarAsset
                              : null,
                        );
                      },
                    ),
            ),

            // Speaking / Thinking live status pill
            if (chat.isLoading)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isAf
                          ? '${character.name} dink...'
                          : '${character.name} is thinking...',
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),

            // Input bar docked securely above soft keyboard
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
              child: Row(
                children: [
                  VoiceButton(
                    isListening: chat.isListening,
                    isSpeaking: chat.isSpeaking,
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            isAf
                                ? 'Stemopname word verwerk. Tik gerus jou boodskap of vra enige vraag.'
                                : 'Full realtime voice pipeline is scaffolded. Text chat is active.',
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 15),
                      decoration: InputDecoration(
                        hintText: isAf ? 'Tik jou boodskap...' : 'Type a message...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: chat.isLoading ? null : _send,
                    style: IconButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: AppTheme.background,
                      padding: const EdgeInsets.all(12),
                    ),
                    icon: const Icon(Icons.send_rounded, size: 20),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Character switching bar matching web companion
  Widget _buildCharacterBar(SettingsProvider settings) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Row(
        children: CharacterRegistry.characters.map((c) {
          final isSelected = c.id == settings.activeCharacter.id;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              avatar: ClipOval(
                child: Image.asset(
                  c.avatarAsset,
                  width: 22,
                  height: 22,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Icon(
                    c.icon,
                    size: 16,
                    color: isSelected ? AppTheme.background : AppTheme.textSecondary,
                  ),
                ),
              ),
              label: Text(c.name),
              selected: isSelected,
              onSelected: (_) => settings.setCharacterId(c.id),
              backgroundColor: AppTheme.surfaceLight.withOpacity(0.5),
              selectedColor: AppTheme.primary,
              labelStyle: TextStyle(
                color: isSelected ? AppTheme.background : AppTheme.textPrimary,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                fontSize: 13,
              ),
              side: BorderSide(
                color: isSelected
                    ? AppTheme.primary
                    : AppTheme.border.withOpacity(0.6),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// Keyboard-safe adaptive hero avatar empty state (guaranteed zero pixel overflows)
  Widget _buildAdaptiveHeroEmptyState(
    BuildContext context,
    SettingsProvider settings,
    CharacterProfile character,
    bool isAf,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Photographic Hero Avatar with live status ring
                    Container(
                      width: 108,
                      height: 108,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppTheme.primary.withOpacity(0.85),
                          width: 3,
                        ),
                        boxShadow: AppTheme.glow(AppTheme.primary, blur: 24, spread: 2),
                      ),
                      child: ClipOval(
                        child: Image.asset(
                          character.avatarAsset,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Icon(
                            character.icon,
                            size: 54,
                            color: AppTheme.primary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      isAf
                          ? 'Luister saam met ${character.name}'
                          : 'Listen with ${character.name}',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                        letterSpacing: 0.3,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      character.getTagline(isAf),
                      style: const TextStyle(
                        color: AppTheme.primary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      character.getDescription(isAf),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppTheme.textSecondary.withOpacity(0.85),
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Quick starter chips for instant zero-effort engagement
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        _buildStarterChip(
                          isAf ? 'Hallo ${character.name}!' : 'Hello ${character.name}!',
                        ),
                        _buildStarterChip(
                          isAf ? 'Hoe voel jy vandag?' : 'How are you today?',
                        ),
                        _buildStarterChip(
                          isAf ? 'Wat is fotosintese?' : 'What is photosynthesis?',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStarterChip(String prompt) {
    return ActionChip(
      label: Text(
        prompt,
        style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12),
      ),
      backgroundColor: AppTheme.surfaceLight.withOpacity(0.7),
      side: BorderSide(color: AppTheme.primary.withOpacity(0.35)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onPressed: () {
        _controller.text = prompt;
        _send();
      },
    );
  }
}
