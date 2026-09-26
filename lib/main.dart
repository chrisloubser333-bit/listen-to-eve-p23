import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'models/ai_provider_type.dart';
import 'providers/chat_provider.dart';
import 'providers/settings_provider.dart';
import 'screens/chat_screen.dart';
import 'services/ai_service.dart';
import 'services/gemini_service.dart';
import 'services/image_proxy_transport.dart';
import 'services/intelligence_orchestrator.dart';
import 'services/memory_service.dart';
import 'services/switchable_ai_service.dart';
import 'services/xai_service.dart';
import 'services/storage_service.dart';
import 'services/weather_tool.dart';
import 'services/web_search_tool.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

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

  // Retrieve saved server base URL and individual proxy endpoints
  final savedServerBaseUrl = await storage.getServerBaseUrl();
  const envServerBaseUrl = String.fromEnvironment(
    'SERVER_BASE_URL',
    defaultValue: '',
  );
  final effectiveServerBaseUrl = (savedServerBaseUrl != null && savedServerBaseUrl.isNotEmpty)
      ? savedServerBaseUrl
      : (envServerBaseUrl.isNotEmpty ? envServerBaseUrl : null);

  final savedProxyEndpoint = await storage.getSearchProxyEndpoint();
  const envProxyEndpoint = String.fromEnvironment(
    'SEARCH_PROXY_ENDPOINT',
    defaultValue: '',
  );
  final effectiveProxyEndpoint = (savedProxyEndpoint != null && savedProxyEndpoint.isNotEmpty)
      ? savedProxyEndpoint
      : (envProxyEndpoint.isNotEmpty
          ? envProxyEndpoint
          : (effectiveServerBaseUrl != null ? '$effectiveServerBaseUrl/api/search' : '/api/search'));

  final savedImageProxyEndpoint = await storage.getImageProxyEndpoint();
  const envImageProxyEndpoint = String.fromEnvironment(
    'IMAGE_PROXY_ENDPOINT',
    defaultValue: '',
  );
  final effectiveImageProxyEndpoint = (savedImageProxyEndpoint != null && savedImageProxyEndpoint.isNotEmpty)
      ? savedImageProxyEndpoint
      : (envImageProxyEndpoint.isNotEmpty
          ? envImageProxyEndpoint
          : (effectiveServerBaseUrl != null ? '$effectiveServerBaseUrl/api/generate-image' : '/api/generate-image'));

  // Initialize secure image proxy transport with serverBaseUrl and fallbacks
  final imageProxyTransport = BackendProxyImageTransport(
    proxyEndpoint: effectiveImageProxyEndpoint,
    serverBaseUrl: effectiveServerBaseUrl,
    fallbackServerUrl: (savedProxyEndpoint != null && savedProxyEndpoint.isNotEmpty)
        ? savedProxyEndpoint
        : (envProxyEndpoint.isNotEmpty ? envProxyEndpoint : effectiveServerBaseUrl),
  );

  // Switchable AI service routes requests to whichever provider is active
  final switchableAi = SwitchableAiService(
    providers: {
      AiProviderType.xai: xaiService,
      AiProviderType.gemini: geminiService,
    },
    initialType: initialProviderType,
    imageProxyTransport: imageProxyTransport,
  );

  final orchestrator = IntelligenceOrchestrator();
  final settingsProvider = SettingsProvider(storage, switchableAi, orchestrator);

  // Register provider-independent intelligence tools
  final weatherTool = WeatherTool();
  orchestrator.registerTool(weatherTool);

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
    final darkMode = context.watch<SettingsProvider>().darkMode;
    final overlayStyle = darkMode
        ? SystemUiOverlayStyle.light.copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: AppTheme.background,
            systemNavigationBarIconBrightness: Brightness.light,
          )
        : SystemUiOverlayStyle.dark.copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: AppTheme.lightBackground,
            systemNavigationBarIconBrightness: Brightness.dark,
          );

    SystemChrome.setSystemUIOverlayStyle(overlayStyle);

    return MaterialApp(
      title: 'Listen to Eve',
      debugShowCheckedModeBanner: false,
      themeMode: darkMode ? ThemeMode.dark : ThemeMode.light,
      darkTheme: AppTheme.darkTheme,
      theme: AppTheme.lightTheme,
      home: const ChatScreen(),
    );
  }
}
