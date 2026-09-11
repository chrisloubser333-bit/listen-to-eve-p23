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
  bool _bannerDismissed = false;
  bool _showScrollToBottom = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    final isScrolledUp = (maxScroll - currentScroll) > 120;
    if (isScrolledUp != _showScrollToBottom) {
      setState(() => _showScrollToBottom = isScrolledUp);
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        if (animate) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        } else {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      }
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    _scrollToBottom();
    final chat = context.read<ChatProvider>();
    await chat.sendText(text);
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final settings = context.watch<SettingsProvider>();
    final character = settings.activeCharacter;
    final isAf = settings.language == 'af';

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
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    character.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  Text(
                    chat.isLoading
                        ? (isAf ? '${character.name} dink...' : '${character.name} is thinking...')
                        : (isAf ? 'Aktief' : 'Active'),
                    style: TextStyle(
                      fontSize: 12,
                      color: chat.isLoading ? Colors.amber : AppTheme.primary,
                    ),
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

            // Persistent top avatar stage: Avatar stays visible while conversation scrolls underneath
            _buildPersistentTopAvatarStage(context, character, isAf, chat),

            // Optional non-blocking API tip banner
            if (!chat.hasApiKey && !_bannerDismissed)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 2, 16, 6),
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
                margin: const EdgeInsets.fromLTRB(16, 2, 16, 6),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.withOpacity(0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        chat.error!,
                        style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12),
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

            // Scrollable conversation area (Always scrollable, tap to dismiss keyboard)
            Expanded(
              child: Stack(
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => FocusScope.of(context).unfocus(),
                    child: chat.messages.isEmpty
                        ? _buildEmptyStarterSuggestions(character, isAf)
                        : ListView.builder(
                            controller: _scrollController,
                            // AlwaysScrollableScrollPhysics ensures touch scrolling works even on 1 or 2 messages
                            physics: const AlwaysScrollableScrollPhysics(
                              parent: BouncingScrollPhysics(),
                            ),
                            // Dismisses keyboard naturally when swiping down the chat
                            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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

                  // Floating Quick Scroll-to-Bottom Pill
                  if (_showScrollToBottom)
                    Positioned(
                      bottom: 12,
                      right: 16,
                      child: FloatingActionButton.small(
                        backgroundColor: AppTheme.surfaceLight,
                        foregroundColor: AppTheme.primary,
                        elevation: 4,
                        onPressed: () => _scrollToBottom(),
                        child: const Icon(Icons.keyboard_arrow_down, size: 24),
                      ),
                    ),
                ],
              ),
            ),

            // Speaking / Thinking live status indicator
            if (chat.isLoading)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
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
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
              child: Row(
                children: [
                  VoiceButton(
                    isListening: chat.isListening,
                    isSpeaking: chat.isSpeaking,
                    onPressed: () async {
                      if (chat.isSpeaking) {
                        await chat.stopSpeaking();
                        return;
                      }
                      await chat.toggleListening(
                        onPartialText: (partial) {
                          setState(() {
                            _controller.text = partial;
                          });
                        },
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
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
                    color: isSelected ? AppTheme.background : AppTheme.primary,
                  ),
                ),
              ),
              label: Text(
                c.name,
                style: TextStyle(
                  color: isSelected ? AppTheme.background : AppTheme.textPrimary,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 13,
                ),
              ),
              selected: isSelected,
              onSelected: (_) => settings.setCharacterId(c.id),
              backgroundColor: AppTheme.surface,
              selectedColor: AppTheme.primary,
              checkmarkColor: AppTheme.background,
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

  /// Persistent Top Avatar Stage (RULE 4: Avatar remains visible while conversation scrolls underneath)
  Widget _buildPersistentTopAvatarStage(
    BuildContext context,
    CharacterProfile character,
    bool isAf,
    ChatProvider chat,
  ) {
    final statusText = chat.isLoading
        ? (isAf ? '${character.name} dink...' : '${character.name} is thinking...')
        : chat.isSpeaking
            ? (isAf ? '${character.name} praat...' : '${character.name} is speaking...')
            : chat.isListening
                ? (isAf ? 'Luister tans...' : 'Listening...')
                : character.getTagline(isAf);

    final statusColor = chat.isLoading
        ? Colors.amber
        : chat.isSpeaking
            ? AppTheme.secondary
            : AppTheme.primary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        color: AppTheme.background,
        border: Border(
          bottom: BorderSide(
            color: AppTheme.border.withOpacity(0.35),
            width: 1,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Photographic Avatar with live status glow halo (tap to stop speech)
          GestureDetector(
            onTap: () {
              if (chat.isSpeaking) {
                chat.stopSpeaking();
              }
            },
            child: Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: statusColor.withOpacity(0.85),
                width: 3.0,
              ),
              boxShadow: AppTheme.glow(statusColor, blur: 22, spread: 2),
            ),
            child: ClipOval(
              child: Image.asset(
                character.avatarAsset,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Icon(
                  character.icon,
                  size: 52,
                  color: statusColor,
                ),
              ),
            ),
          ),
          ),
          const SizedBox(height: 6),
          // Character Name
          Text(
            character.name,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 2),
          // Status Indicator Dot & Status Message
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: statusColor,
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  statusText,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Empty state starter suggestions
  Widget _buildEmptyStarterSuggestions(
    CharacterProfile character,
    bool isAf,
  ) {
    return Center(
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              character.getDescription(isAf),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.textSecondary.withOpacity(0.9),
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
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
