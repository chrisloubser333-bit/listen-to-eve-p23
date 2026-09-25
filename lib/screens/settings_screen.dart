import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/character_profile.dart';
import '../providers/settings_provider.dart';
import '../providers/chat_provider.dart';
import '../theme/app_theme.dart';
import 'memory_screen.dart';
import 'voice_recorder_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _apiKeyController = TextEditingController();
  final _serverBaseUrlController = TextEditingController();
  final _proxyController = TextEditingController();
  final _imageProxyController = TextEditingController();
  bool _obscureKey = true;
  bool _serverBaseUrlInit = false;
  bool _proxyInit = false;
  bool _imageProxyInit = false;

  @override
  void dispose() {
    _apiKeyController.dispose();
    _serverBaseUrlController.dispose();
    _proxyController.dispose();
    _imageProxyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final chat = context.watch<ChatProvider>();
    final isAf = settings.language == 'af';

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(isAf ? 'Instellings' : 'Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // AI Provider selection
          _sectionTitle(isAf ? 'KI-verskaffer' : 'AI Provider'),
          _glassCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  _providerChip(
                    'xai',
                    'xAI (Grok)',
                    settings.aiProvider == 'xai',
                    () => settings.setAiProvider('xai'),
                  ),
                  const SizedBox(width: 10),
                  _providerChip(
                    'gemini',
                    'Google Gemini',
                    settings.aiProvider == 'gemini',
                    () => settings.setAiProvider('gemini'),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 28),

          // API Key for Active Provider
          _sectionTitle(settings.aiProvider == 'gemini'
              ? (isAf ? 'Google Gemini API-sleutel' : 'Google Gemini API Key')
              : (isAf ? 'xAI API-sleutel' : 'xAI API Key')),
          _glassCard(
            child: TextField(
              controller: _apiKeyController,
              obscureText: _obscureKey,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                hintText: chat.hasApiKey
                    ? '••••••••••••••••'
                    : (settings.aiProvider == 'gemini'
                        ? 'AIzaSy...'
                        : 'xai-...'),
                hintStyle: const TextStyle(color: AppTheme.textSecondary),
                border: InputBorder.none,
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(
                        _obscureKey ? Icons.visibility : Icons.visibility_off,
                        color: AppTheme.textSecondary,
                      ),
                      onPressed: () =>
                          setState(() => _obscureKey = !_obscureKey),
                    ),
                    IconButton(
                      icon: const Icon(Icons.save_rounded,
                          color: AppTheme.primary),
                      onPressed: () async {
                        final key = _apiKeyController.text.trim();
                        if (key.isNotEmpty) {
                          final messenger = ScaffoldMessenger.of(context);
                          await chat.setApiKey(key);
                          if (mounted) {
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(isAf
                                    ? 'API-sleutel gestoor'
                                    : 'API key saved'),
                              ),
                            );
                            _apiKeyController.clear();
                          }
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            settings.aiProvider == 'gemini'
                ? (isAf
                    ? 'Kry jou sleutel by aistudio.google.com. Moet nooit openbaar deel nie.'
                    : 'Get your key at aistudio.google.com. Never share it publicly.')
                : (isAf
                    ? 'Kry jou sleutel by console.x.ai. Moet nooit openbaar deel nie.'
                    : 'Get your key at console.x.ai. Never share it publicly.'),
            style: const TextStyle(
                color: AppTheme.textSecondary, fontSize: 12),
          ),

          const SizedBox(height: 28),

          // Language
          _sectionTitle(isAf ? 'Taal' : 'Language'),
          _glassCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  _langChip('en', 'English', settings.language == 'en', () {
                    settings.setLanguage('en');
                  }),
                  const SizedBox(width: 10),
                  _langChip('af', 'Afrikaans', settings.language == 'af', () {
                    settings.setLanguage('af');
                  }),
                ],
              ),
            ),
          ),

          const SizedBox(height: 28),

          // Character / Persona selection
          _sectionTitle(isAf ? 'Karakter / Persona' : 'Character / Persona'),
          ...CharacterRegistry.characters.map((character) {
            final selected = character.id == settings.characterId;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _glassCard(
                borderColor: selected
                    ? AppTheme.primary.withOpacity(0.7)
                    : null,
                glow: selected,
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected ? AppTheme.primary : AppTheme.border,
                        width: 1.5,
                      ),
                      boxShadow: selected ? AppTheme.glow(AppTheme.primary, blur: 8, spread: 0) : null,
                    ),
                    child: ClipOval(
                      child: Image.asset(
                        character.avatarAsset,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Icon(
                          character.icon,
                          size: 20,
                          color: selected ? AppTheme.primary : AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  title: Row(
                    children: [
                      Text(
                        character.name,
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? AppTheme.primary.withOpacity(0.18)
                              : Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          character.getTagline(isAf),
                          style: TextStyle(
                            color: selected
                                ? AppTheme.primary
                                : AppTheme.textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      character.getDescription(isAf),
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  trailing: selected
                      ? const Icon(
                          Icons.check_circle_rounded,
                          color: AppTheme.primary,
                        )
                      : null,
                  onTap: () => settings.setCharacterId(character.id),
                ),
              ),
            );
          }),

          const SizedBox(height: 28),

          // Voice selection
          _sectionTitle(isAf ? 'Stem' : 'Voice'),
          ...settings.allVoices.map((voice) {
            final selected = voice.id == settings.voiceId;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _glassCard(
                borderColor: selected
                    ? AppTheme.primary.withOpacity(0.6)
                    : null,
                glow: selected,
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  leading: Icon(
                    voice.isCustom
                        ? Icons.record_voice_over_rounded
                        : Icons.person_rounded,
                    color: selected ? AppTheme.primary : AppTheme.textSecondary,
                  ),
                  title: Text(
                    voice.name,
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                  subtitle: Text(
                    voice.description,
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 13),
                  ),
                  trailing: selected
                      ? const Icon(Icons.check_circle_rounded,
                          color: AppTheme.primary)
                      : null,
                  onTap: () => settings.setVoiceId(voice.id),
                ),
              ),
            );
          }),

          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const VoiceRecorderScreen(),
                ),
              );
            },
            icon: const Icon(Icons.add_rounded),
            label: Text(isAf ? 'Leer \'n nuwe stem' : 'Teach a new voice'),
          ),

          const SizedBox(height: 20),

          // Voice Interaction Controls (Speech silence pause & auto voice reply)
          _sectionTitle(isAf ? 'Steminteraksie & Pouse' : 'Speech & Silence Detection'),
          _glassCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        isAf ? 'Stiltestoppause' : 'Silence Pause Before Send',
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${settings.silencePauseSeconds.toStringAsFixed(1)}s',
                          style: const TextStyle(
                            color: AppTheme.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isAf
                        ? 'Wagtyd sonder spraak voor boodskap outomaties gestuur word (1.0s - 3.0s).'
                        : 'How long Eve waits in silence before automatically sending your speech.',
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: AppTheme.primary,
                      inactiveTrackColor: AppTheme.border,
                      thumbColor: AppTheme.primary,
                    ),
                    child: Slider(
                      value: settings.silencePauseSeconds,
                      min: 1.0,
                      max: 3.0,
                      divisions: 20,
                      onChanged: (val) => settings.setSilencePauseSeconds(val),
                    ),
                  ),
                  const Divider(color: AppTheme.border, height: 16),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      isAf ? 'Lees antwoorde hardop' : 'Speak Responses Aloud',
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    subtitle: Text(
                      isAf
                          ? 'Elke karakter antwoord met hul eie unieke stem'
                          : 'Each character replies using their unique human-like voice',
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                    ),
                    value: settings.autoVoiceReply,
                    activeThumbColor: AppTheme.primary,
                    onChanged: (val) => settings.setAutoVoiceReply(val),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 28),

          // Memory
          _sectionTitle(isAf ? 'Geheue' : 'Memory'),
          _glassCard(
            child: ListTile(
              leading: const Icon(Icons.psychology_rounded,
                  color: AppTheme.secondary),
              title: Text(
                isAf ? 'Bestuur geheue' : 'Manage memory',
                style: const TextStyle(color: AppTheme.textPrimary),
              ),
              subtitle: Text(
                isAf
                    ? 'Sien en beheer wat ${settings.activeCharacter.name} onthou'
                    : 'View and control what ${settings.activeCharacter.name} remembers',
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 13),
              ),
              trailing: const Icon(Icons.chevron_right_rounded,
                  color: AppTheme.textSecondary),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const MemoryScreen()),
                );
              },
            ),
          ),

          const SizedBox(height: 28),

          // Appearance
          _sectionTitle(isAf ? 'Voorkoms' : 'Appearance'),
          _glassCard(
            child: SwitchListTile(
              title: Text(
                isAf ? 'Donker futuristiese tema' : 'Dark futuristic theme',
                style: const TextStyle(color: AppTheme.textPrimary),
              ),
              subtitle: Text(
                isAf ? 'Altyd aktief in hierdie weergawe' : 'Always on in this version',
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 13),
              ),
              value: true,
              onChanged: null, // locked to futuristic dark for now
            ),
          ),

          const SizedBox(height: 28),

          // Server Base URL Configuration (Primary endpoint for Image Generation, Search, and Cloud backend)
          _sectionTitle(isAf ? 'Bediener-URL (Hoof-eindpunt)' : 'Server Base URL (Primary Endpoint)'),
          _glassCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _serverBaseUrlController..text = (!_serverBaseUrlInit
                        ? (settings.serverBaseUrl ?? '')
                        : _serverBaseUrlController.text),
                    onChanged: (_) => _serverBaseUrlInit = true,
                    style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'https://your-server.run.app or http://192.168.1.50:3000',
                      hintStyle: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                      border: InputBorder.none,
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.save_rounded, color: AppTheme.primary),
                        onPressed: () async {
                          final url = _serverBaseUrlController.text.trim();
                          final messenger = ScaffoldMessenger.of(context);
                          await settings.setServerBaseUrl(url);
                          if (mounted) {
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(isAf
                                    ? 'Bediener-URL gestoor'
                                    : 'Server Base URL saved'),
                              ),
                            );
                          }
                        },
                      ),
                    ),
                  ),
                  Text(
                    isAf
                        ? 'Stel die primêre bediener vir prentgenerering (/api/generate-image) en lewendige soektogte (/api/search) op Android op. Moenie localhost op \'n fisiese foon gebruik nie.'
                        : 'Configures your backend server for image generation (/api/generate-image) and web search (/api/search) on Android. Do not use localhost on a physical phone.',
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 28),

          // Web Search Proxy Configuration (for physical Android devices and custom backends)
          _sectionTitle(isAf ? 'Spesifieke websoek-eindpunt (Opsioneel)' : 'Custom Web Search Endpoint (Optional)'),
          _glassCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _proxyController..text = (!_proxyInit
                        ? (settings.searchProxyEndpoint ?? '')
                        : _proxyController.text),
                    onChanged: (_) => _proxyInit = true,
                    style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'https://your-search-proxy.run.app/api/search',
                      hintStyle: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                      border: InputBorder.none,
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.save_rounded, color: AppTheme.primary),
                        onPressed: () async {
                          final endpoint = _proxyController.text.trim();
                          final messenger = ScaffoldMessenger.of(context);
                          await settings.setSearchProxyEndpoint(endpoint);
                          if (mounted) {
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(isAf
                                    ? 'Websoek-eindpunt gestoor'
                                    : 'Search proxy endpoint saved'),
                              ),
                            );
                          }
                        },
                      ),
                    ),
                  ),
                  Text(
                    isAf
                        ? 'Oorskryf die soek-eindpunt slegs as dit verskil van die Bediener-URL. Laat leeg om Bediener-URL te gebruik.'
                        : 'Overrides web search endpoint only if different from Server Base URL. Leave empty to use Server Base URL.',
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 28),

          // Image Generation Proxy Configuration (for physical Android APK and cloud backends)
          _sectionTitle(isAf ? 'Spesifieke prentgenerering-eindpunt (Opsioneel)' : 'Custom Image Generation Endpoint (Optional)'),
          _glassCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _imageProxyController..text = (!_imageProxyInit
                        ? (settings.imageProxyEndpoint ?? '')
                        : _imageProxyController.text),
                    onChanged: (_) => _imageProxyInit = true,
                    style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'https://your-server.run.app/api/generate-image',
                      hintStyle: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                      border: InputBorder.none,
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.save_rounded, color: AppTheme.primary),
                        onPressed: () async {
                          final endpoint = _imageProxyController.text.trim();
                          final messenger = ScaffoldMessenger.of(context);
                          await settings.setImageProxyEndpoint(endpoint);
                          if (mounted) {
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(isAf
                                    ? 'Beeldgenerering-eindpunt gestoor'
                                    : 'Image proxy endpoint saved'),
                              ),
                            );
                          }
                        },
                      ),
                    ),
                  ),
                  Text(
                    isAf
                        ? 'Oorskryf die prentgenerering-eindpunt slegs as dit verskil van die Bediener-URL. Laat leeg om Bediener-URL te gebruik.'
                        : 'Overrides image endpoint only if different from Server Base URL. Leave empty to use Server Base URL.',
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 28),

          // Danger zone
          _sectionTitle(isAf ? 'Gevaar sone' : 'Danger zone'),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFFF6B6B),
              side: const BorderSide(color: Color(0xFFFF6B6B)),
            ),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: AppTheme.surface,
                  title: Text(
                    isAf ? 'Vee kletsgeskiedenis uit?' : 'Clear chat history?',
                    style: const TextStyle(color: AppTheme.textPrimary),
                  ),
                  content: Text(
                    isAf
                        ? 'Dit kan nie ongedaan gemaak word nie.'
                        : 'This cannot be undone.',
                    style: const TextStyle(color: AppTheme.textSecondary),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text(isAf ? 'Kanselleer' : 'Cancel'),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFFF6B6B)),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text(isAf ? 'Vee uit' : 'Clear'),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                await chat.clearHistory();
              }
            },
            icon: const Icon(Icons.delete_outline_rounded),
            label: Text(isAf
                ? 'Vee kletsgeskiedenis uit'
                : 'Clear chat history'),
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

  Widget _glassCard({
    required Widget child,
    Color? borderColor,
    bool glow = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: borderColor ?? AppTheme.border.withOpacity(0.6),
        ),
        boxShadow: glow ? AppTheme.glow(AppTheme.primary, blur: 12) : null,
      ),
      child: child,
    );
  }

  Widget _langChip(
      String code, String label, bool selected, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.primary.withOpacity(0.18)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? AppTheme.primary.withOpacity(0.7)
                  : AppTheme.border.withOpacity(0.5),
            ),
            boxShadow: selected
                ? AppTheme.glow(AppTheme.primary, blur: 8, spread: 0)
                : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? AppTheme.primary : AppTheme.textSecondary,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _providerChip(
      String code, String label, bool selected, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.primary.withOpacity(0.18)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? AppTheme.primary.withOpacity(0.7)
                  : AppTheme.border.withOpacity(0.5),
            ),
            boxShadow: selected
                ? AppTheme.glow(AppTheme.primary, blur: 8, spread: 0)
                : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? AppTheme.primary : AppTheme.textSecondary,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
