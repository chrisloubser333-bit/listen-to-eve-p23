import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/character_profile.dart';
import '../providers/chat_provider.dart';
import '../providers/settings_provider.dart';
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

  ColorScheme get _scheme => Theme.of(context).colorScheme;
  Color get _primary => _scheme.primary;
  Color get _text => _scheme.onSurface;
  Color get _muted => _scheme.onSurfaceVariant;
  Color get _border => _scheme.outline;

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
      appBar: AppBar(title: Text(isAf ? 'Instellings' : 'Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _sectionTitle(isAf ? 'KI-verskaffer' : 'AI Provider'),
          _glassCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                _choiceChip('xAI (Grok)', settings.aiProvider == 'xai', () => settings.setAiProvider('xai')),
                const SizedBox(width: 10),
                _choiceChip('Google Gemini', settings.aiProvider == 'gemini', () => settings.setAiProvider('gemini')),
              ]),
            ),
          ),
          const SizedBox(height: 28),

          _sectionTitle(settings.aiProvider == 'gemini'
              ? (isAf ? 'Google Gemini API-sleutel' : 'Google Gemini API Key')
              : (isAf ? 'xAI API-sleutel' : 'xAI API Key')),
          _glassCard(
            child: TextField(
              controller: _apiKeyController,
              obscureText: _obscureKey,
              style: TextStyle(color: _text),
              decoration: InputDecoration(
                hintText: chat.hasApiKey ? '••••••••••••••••' : (settings.aiProvider == 'gemini' ? 'AIzaSy...' : 'xai-...'),
                border: InputBorder.none,
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(_obscureKey ? Icons.visibility : Icons.visibility_off, color: _muted),
                      onPressed: () => setState(() => _obscureKey = !_obscureKey),
                    ),
                    IconButton(
                      icon: Icon(Icons.save_rounded, color: _primary),
                      onPressed: () async {
                        final key = _apiKeyController.text.trim();
                        if (key.isEmpty) return;
                        final messenger = ScaffoldMessenger.of(context);
                        await chat.setApiKey(key);
                        if (!mounted) return;
                        messenger.showSnackBar(SnackBar(content: Text(isAf ? 'API-sleutel gestoor' : 'API key saved')));
                        _apiKeyController.clear();
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
                ? (isAf ? 'Kry jou sleutel by aistudio.google.com. Moet nooit openbaar deel nie.' : 'Get your key at aistudio.google.com. Never share it publicly.')
                : (isAf ? 'Kry jou sleutel by console.x.ai. Moet nooit openbaar deel nie.' : 'Get your key at console.x.ai. Never share it publicly.'),
            style: TextStyle(color: _muted, fontSize: 12),
          ),
          const SizedBox(height: 28),

          _sectionTitle(isAf ? 'Taal' : 'Language'),
          _glassCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                _choiceChip('English', settings.language == 'en', () => settings.setLanguage('en')),
                const SizedBox(width: 10),
                _choiceChip('Afrikaans', settings.language == 'af', () => settings.setLanguage('af')),
              ]),
            ),
          ),
          const SizedBox(height: 28),

          _sectionTitle(isAf ? 'Karakter / Persona' : 'Character / Persona'),
          ...CharacterRegistry.characters.map((character) {
            final selected = character.id == settings.characterId;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _glassCard(
                selected: selected,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: selected ? _primary : _border, width: 1.5),
                    ),
                    child: ClipOval(
                      child: Image.asset(
                        character.avatarAsset,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Icon(character.icon, size: 20, color: selected ? _primary : _muted),
                      ),
                    ),
                  ),
                  title: Text(
                    character.name,
                    style: TextStyle(color: _text, fontWeight: selected ? FontWeight.w600 : FontWeight.w500),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(character.getDescription(isAf), style: TextStyle(color: _muted, fontSize: 12)),
                  ),
                  trailing: selected ? Icon(Icons.check_circle_rounded, color: _primary) : null,
                  onTap: () => settings.setCharacterId(character.id),
                ),
              ),
            );
          }),
          const SizedBox(height: 20),

          _sectionTitle(isAf ? 'Stem' : 'Voice'),
          ...settings.allVoices.map((voice) {
            final selected = voice.id == settings.voiceId;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _glassCard(
                selected: selected,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  leading: Icon(voice.isCustom ? Icons.record_voice_over_rounded : Icons.person_rounded, color: selected ? _primary : _muted),
                  title: Text(voice.name, style: TextStyle(color: _text, fontWeight: selected ? FontWeight.w600 : FontWeight.w500)),
                  subtitle: Text(voice.description, style: TextStyle(color: _muted, fontSize: 13)),
                  trailing: selected ? Icon(Icons.check_circle_rounded, color: _primary) : null,
                  onTap: () => settings.setVoiceId(voice.id),
                ),
              ),
            );
          }),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const VoiceRecorderScreen())),
            icon: const Icon(Icons.add_rounded),
            label: Text(isAf ? 'Leer ’n nuwe stem' : 'Teach a new voice'),
          ),
          const SizedBox(height: 20),

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
                      Flexible(child: Text(isAf ? 'Stiltestoppause' : 'Silence Pause Before Send', style: TextStyle(color: _text, fontWeight: FontWeight.w600, fontSize: 14))),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: _primary.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
                        child: Text('${settings.silencePauseSeconds.toStringAsFixed(1)}s', style: TextStyle(color: _primary, fontWeight: FontWeight.bold, fontSize: 13)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isAf ? 'Wagtyd sonder spraak voor boodskap outomaties gestuur word (1.0s - 3.0s).' : 'How long Eve waits in silence before automatically sending your speech.',
                    style: TextStyle(color: _muted, fontSize: 12),
                  ),
                  Slider(
                    value: settings.silencePauseSeconds,
                    min: 1.0,
                    max: 3.0,
                    divisions: 20,
                    onChanged: settings.setSilencePauseSeconds,
                  ),
                  Divider(color: _border.withValues(alpha: 0.6), height: 16),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(isAf ? 'Lees antwoorde hardop' : 'Speak Responses Aloud', style: TextStyle(color: _text, fontSize: 14, fontWeight: FontWeight.w500)),
                    subtitle: Text(
                      isAf ? 'Elke karakter antwoord met hul eie unieke stem' : 'Each character replies using their unique human-like voice',
                      style: TextStyle(color: _muted, fontSize: 12),
                    ),
                    value: settings.autoVoiceReply,
                    onChanged: settings.setAutoVoiceReply,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 28),

          _sectionTitle(isAf ? 'Geheue' : 'Memory'),
          _glassCard(
            child: ListTile(
              leading: Icon(Icons.psychology_rounded, color: _scheme.secondary),
              title: Text(isAf ? 'Bestuur geheue' : 'Manage memory', style: TextStyle(color: _text)),
              subtitle: Text(
                isAf ? 'Sien en beheer wat ${settings.activeCharacter.name} onthou' : 'View and control what ${settings.activeCharacter.name} remembers',
                style: TextStyle(color: _muted, fontSize: 13),
              ),
              trailing: Icon(Icons.chevron_right_rounded, color: _muted),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MemoryScreen())),
            ),
          ),
          const SizedBox(height: 28),

          _sectionTitle(isAf ? 'Voorkoms' : 'Appearance'),
          _glassCard(
            child: SwitchListTile(
              secondary: Icon(settings.darkMode ? Icons.dark_mode_rounded : Icons.light_mode_rounded, color: _primary),
              title: Text(isAf ? 'Donker tema' : 'Dark theme', style: TextStyle(color: _text)),
              subtitle: Text(
                settings.darkMode
                    ? (isAf ? 'Donker modus is aktief' : 'Dark mode is active')
                    : (isAf ? 'Ligte modus is aktief' : 'Light mode is active'),
                style: TextStyle(color: _muted, fontSize: 13),
              ),
              value: settings.darkMode,
              onChanged: settings.setDarkMode,
            ),
          ),
          const SizedBox(height: 28),

          _sectionTitle(isAf ? 'Bediener-URL (Hoof-eindpunt)' : 'Server Base URL (Primary Endpoint)'),
          _endpointCard(
            controller: _serverBaseUrlController,
            initialValue: settings.serverBaseUrl ?? '',
            initialized: _serverBaseUrlInit,
            onChanged: () => _serverBaseUrlInit = true,
            hint: 'https://your-server.run.app or http://192.168.1.50:3000',
            help: isAf
                ? 'Stel die primêre bediener vir prentgenerering (/api/generate-image) en lewendige soektogte (/api/search) op Android op. Moenie localhost op ’n fisiese foon gebruik nie.'
                : 'Configures your backend server for image generation (/api/generate-image) and web search (/api/search) on Android. Do not use localhost on a physical phone.',
            onSave: () async {
              final messenger = ScaffoldMessenger.of(context);
              await settings.setServerBaseUrl(_serverBaseUrlController.text.trim());
              if (mounted) messenger.showSnackBar(SnackBar(content: Text(isAf ? 'Bediener-URL gestoor' : 'Server Base URL saved')));
            },
          ),
          const SizedBox(height: 28),

          _sectionTitle(isAf ? 'Spesifieke websoek-eindpunt (Opsioneel)' : 'Custom Web Search Endpoint (Optional)'),
          _endpointCard(
            controller: _proxyController,
            initialValue: settings.searchProxyEndpoint ?? '',
            initialized: _proxyInit,
            onChanged: () => _proxyInit = true,
            hint: 'https://your-search-proxy.run.app/api/search',
            help: isAf ? 'Oorskryf die soek-eindpunt slegs as dit verskil van die Bediener-URL. Laat leeg om Bediener-URL te gebruik.' : 'Overrides web search endpoint only if different from Server Base URL. Leave empty to use Server Base URL.',
            onSave: () async {
              final messenger = ScaffoldMessenger.of(context);
              await settings.setSearchProxyEndpoint(_proxyController.text.trim());
              if (mounted) messenger.showSnackBar(SnackBar(content: Text(isAf ? 'Websoek-eindpunt gestoor' : 'Search proxy endpoint saved')));
            },
          ),
          const SizedBox(height: 28),

          _sectionTitle(isAf ? 'Spesifieke prentgenerering-eindpunt (Opsioneel)' : 'Custom Image Generation Endpoint (Optional)'),
          _endpointCard(
            controller: _imageProxyController,
            initialValue: settings.imageProxyEndpoint ?? '',
            initialized: _imageProxyInit,
            onChanged: () => _imageProxyInit = true,
            hint: 'https://your-server.run.app/api/generate-image',
            help: isAf ? 'Oorskryf die prentgenerering-eindpunt slegs as dit verskil van die Bediener-URL. Laat leeg om Bediener-URL te gebruik.' : 'Overrides image endpoint only if different from Server Base URL. Leave empty to use Server Base URL.',
            onSave: () async {
              final messenger = ScaffoldMessenger.of(context);
              await settings.setImageProxyEndpoint(_imageProxyController.text.trim());
              if (mounted) messenger.showSnackBar(SnackBar(content: Text(isAf ? 'Beeldgenerering-eindpunt gestoor' : 'Image proxy endpoint saved')));
            },
          ),
          const SizedBox(height: 28),

          _sectionTitle(isAf ? 'Gevaar sone' : 'Danger zone'),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: _scheme.error, side: BorderSide(color: _scheme.error)),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text(isAf ? 'Vee kletsgeskiedenis uit?' : 'Clear chat history?'),
                  content: Text(isAf ? 'Dit kan nie ongedaan gemaak word nie.' : 'This cannot be undone.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(isAf ? 'Kanselleer' : 'Cancel')),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: _scheme.error, foregroundColor: _scheme.onError),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text(isAf ? 'Vee uit' : 'Clear'),
                    ),
                  ],
                ),
              );
              if (confirm == true) await chat.clearHistory();
            },
            icon: const Icon(Icons.delete_outline_rounded),
            label: Text(isAf ? 'Vee kletsgeskiedenis uit' : 'Clear chat history'),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(title, style: TextStyle(color: _text, fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 0.3)),
      );

  Widget _glassCard({required Widget child, bool selected = false}) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: theme.brightness == Brightness.dark ? 0.72 : 0.96),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: selected ? _primary.withValues(alpha: 0.7) : _border.withValues(alpha: 0.55)),
        boxShadow: selected ? [BoxShadow(color: _primary.withValues(alpha: 0.18), blurRadius: 12)] : null,
      ),
      child: child,
    );
  }

  Widget _choiceChip(String label, bool selected, VoidCallback onTap) => Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: selected ? _primary.withValues(alpha: 0.14) : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: selected ? _primary.withValues(alpha: 0.7) : _border.withValues(alpha: 0.5)),
            ),
            child: Text(label, textAlign: TextAlign.center, style: TextStyle(color: selected ? _primary : _muted, fontWeight: selected ? FontWeight.w600 : FontWeight.w500)),
          ),
        ),
      );

  Widget _endpointCard({
    required TextEditingController controller,
    required String initialValue,
    required bool initialized,
    required VoidCallback onChanged,
    required String hint,
    required String help,
    required Future<void> Function() onSave,
  }) {
    if (!initialized && controller.text != initialValue) controller.text = initialValue;
    return _glassCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              onChanged: (_) => onChanged(),
              style: TextStyle(color: _text, fontSize: 14),
              decoration: InputDecoration(
                hintText: hint,
                border: InputBorder.none,
                suffixIcon: IconButton(icon: Icon(Icons.save_rounded, color: _primary), onPressed: onSave),
              ),
            ),
            Text(help, style: TextStyle(color: _muted, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
