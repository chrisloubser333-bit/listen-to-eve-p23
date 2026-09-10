import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../providers/settings_provider.dart';
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

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

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
    final text = _controller.text;
    _controller.clear();
    final chat = context.read<ChatProvider>();
    await chat.sendText(text);
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final settings = context.watch<SettingsProvider>();
    final theme = Theme.of(context);

    // Auto-scroll when new messages arrive
    if (chat.messages.isNotEmpty) {
      _scrollToBottom();
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  settings.activeCharacter.icon,
                  size: 18,
                  color: AppTheme.primary,
                ),
                const SizedBox(width: 8),
                Text(settings.activeCharacter.name),
              ],
            ),
            Text(
              '${settings.language == 'af' ? 'Afrikaans' : 'English'} • ${settings.activeCharacter.getTagline(settings.language == 'af')}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // API key warning
          if (!chat.hasApiKey)
            MaterialBanner(
              content: Text(
                settings.aiProvider == 'gemini'
                    ? (settings.language == 'af'
                        ? 'Stel asseblief jou Google Gemini API-sleutel in Instellings om te begin gesels.'
                        : 'Please set your Google Gemini API key in Settings to start chatting.')
                    : (settings.language == 'af'
                        ? 'Stel asseblief jou xAI API-sleutel in Instellings om te begin gesels.'
                        : 'Please set your xAI API key in Settings to start chatting.'),
              ),
              leading: const Icon(Icons.key),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    );
                  },
                  child: Text(
                    settings.language == 'af' ? 'Instellings' : 'Settings',
                  ),
                ),
              ],
            ),

          // Error banner
          if (chat.error != null)
            MaterialBanner(
              content: Text(chat.error!, maxLines: 3),
              leading: const Icon(Icons.error_outline, color: Colors.red),
              actions: [
                TextButton(
                  onPressed: () => chat.clearError(),
                  child: const Text('Dismiss'),
                ),
              ],
            ),

          // Messages
          Expanded(
            child: chat.messages.isEmpty
                ? _buildEmptyState(context, settings)
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    itemCount: chat.messages.length,
                    itemBuilder: (context, index) {
                      final msg = chat.messages[index];
                      return MessageBubble(message: msg);
                    },
                  ),
          ),

          // Loading indicator
          if (chat.isLoading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
                    settings.language == 'af'
                        ? '${settings.activeCharacter.name} dink...'
                        : '${settings.activeCharacter.name} is thinking...',
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),

          // Input area
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  // Voice button
                  VoiceButton(
                    isListening: chat.isListening,
                    isSpeaking: chat.isSpeaking,
                    onPressed: () {
                      // Placeholder – full realtime voice coming next
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Full realtime voice pipeline is scaffolded. '
                            'Text chat works now. Voice streaming will be completed next.',
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                  // Text field
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: settings.language == 'af'
                            ? 'Tik jou boodskap...'
                            : 'Type a message...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Send button
                  IconButton.filled(
                    onPressed: chat.isLoading ? null : _send,
                    icon: const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, SettingsProvider settings) {
    final isAf = settings.language == 'af';
    final character = settings.activeCharacter;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              character.icon,
              size: 72,
              color: AppTheme.primary.withOpacity(0.8),
            ),
            const SizedBox(height: 20),
            Text(
              isAf
                  ? 'Luister saam met ${character.name}'
                  : 'Listen with ${character.name}',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              character.getTagline(isAf),
              style: TextStyle(
                color: AppTheme.primary.withOpacity(0.85),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              character.getDescription(isAf),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 12),
            Text(
              isAf
                  ? 'Tik \'n boodskap of gebruik die mikrofoon-knoppie.\nJy kan tussen karakters en tale wissel in Instellings.'
                  : 'Type a message or use the microphone button.\nYou can switch characters and languages in Settings.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.textSecondary.withOpacity(0.7),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
