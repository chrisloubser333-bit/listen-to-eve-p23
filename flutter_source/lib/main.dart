import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'models/ai_provider_type.dart';
import 'providers/chat_provider.dart';
import 'providers/settings_provider.dart';
import 'screens/chat_screen.dart';
import 'services/ai_service.dart';
import 'services/gemini_service.dart';
import 'services/intelligence_orchestrator.dart';
import 'services/memory_service.dart';
import 'services/switchable_ai_service.dart';
import 'services/xai_service.dart';
import 'services/storage_service.dart';
import 'services/web_search_tool.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Status bar style for dark futuristic look
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppTheme.background,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  final storage = StorageService();
  await storage.init();

  final memoryService = MemoryService(storage);

  // Initialize concrete AI provider brains
  final xaiService = XaiService();
  final geminiService = GeminiService();

  // Load saved credentials for each provider
  final savedXaiKey = await storage.getApiKeyForProvider('xai');
  if (savedXaiKey != null && savedXaiKey.isNotEmpty) {
    xaiService.setApiKey(savedXaiKey);
  }

  final savedGeminiKey = await storage.getApiKeyForProvider('gemini');
  if (savedGeminiKey != null && savedGeminiKey.isNotEmpty) {
    geminiService.setApiKey(savedGeminiKey);
  }

  final savedProviderId = await storage.getActiveAiProvider();
  final initialProviderType = AiProviderType.fromString(savedProviderId);

  // Switchable AI service routes requests to whichever provider is active
  final switchableAi = SwitchableAiService(
    providers: {
      AiProviderType.xai: xaiService,
      AiProviderType.gemini: geminiService,
    },
    initialType: initialProviderType,
  );

  final settingsProvider = SettingsProvider(storage, switchableAi);
  final orchestrator = IntelligenceOrchestrator();

  // Register provider-independent intelligence tools
  final savedProxyEndpoint = await storage.getSearchProxyEndpoint();
  const envProxyEndpoint = String.fromEnvironment(
    'SEARCH_PROXY_ENDPOINT',
    defaultValue: '',
  );
  final effectiveProxyEndpoint = (savedProxyEndpoint != null && savedProxyEndpoint.isNotEmpty)
      ? savedProxyEndpoint
      : (envProxyEndpoint.isNotEmpty ? envProxyEndpoint : '/api/search');

  final webSearchTool = WebSearchTool(
    transport: BackendProxySearchTransport(
      proxyEndpoint: effectiveProxyEndpoint,
    ),
  );
  orchestrator.registerTool(webSearchTool);

  runApp(
    MultiProvider(
      providers: [
        Provider<AiService>.value(value: switchableAi),
        Provider<IntelligenceOrchestrator>.value(value: orchestrator),
        ChangeNotifierProvider.value(value: settingsProvider),
        ChangeNotifierProvider.value(value: memoryService),
        ChangeNotifierProvider(
          create: (context) => ChatProvider(
            context.read<AiService>(),
            context.read<SettingsProvider>(),
            storage,
            context.read<MemoryService>(),
            context.read<IntelligenceOrchestrator>(),
          ),
        ),
      ],
      child: const LteApp(),
    ),
  );
}

class LteApp extends StatelessWidget {
  const LteApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Force the futuristic dark theme as the primary experience
    return MaterialApp(
      title: 'Listen with Eve',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: AppTheme.darkTheme,
      theme: AppTheme.darkTheme, // also set light to dark for consistency
      home: const ChatScreen(),
    );
  }
}
