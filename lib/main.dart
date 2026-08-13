import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/app_localizations.dart';
import 'package:logging/logging.dart';
import 'package:provider/provider.dart';

import 'domain/interfaces/config_provider.dart';
import 'domain/interfaces/metadata_provider.dart';
import 'domain/interfaces/playlist_strategy.dart';
import 'domain/interfaces/sync_provider.dart';
import 'domain/interfaces/storage_provider.dart';
import 'domain/interfaces/photo_repository.dart';
import 'domain/interfaces/display_controller.dart';
import 'infrastructure/services/app_initializer.dart';
import 'infrastructure/services/json_config_service.dart';
import 'infrastructure/services/exif_metadata_provider.dart';
import 'infrastructure/services/icloud_album_source_config.dart';
import 'infrastructure/services/icloud_album_sync_service.dart';
import 'infrastructure/services/webdav_source_config.dart';
import 'infrastructure/services/webdav_sync_service.dart';
import 'infrastructure/services/noop_sync_service.dart';
import 'infrastructure/services/photo_service.dart';
import 'infrastructure/services/web_server_service.dart';
import 'infrastructure/services/local_storage_provider.dart';
import 'infrastructure/services/native_display_controller.dart';
import 'infrastructure/services/update_service.dart';
import 'infrastructure/repositories/hybrid_photo_repository.dart';
import 'infrastructure/strategies/weighted_freshness_strategy.dart';
import 'ui/dialogs/update_dialog.dart';
import 'ui/screens/slideshow_screen.dart';

/// Used by the auto-updater to show the update prompt over the running app.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  // Setup Logging
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    print('${record.level.name}: ${record.time}: ${record.message}');
    if (record.error != null) {
      print('ERROR: ${record.error}');
    }
    if (record.stackTrace != null) {
      print(record.stackTrace);
    }
  });

  WidgetsFlutterBinding.ensureInitialized();

  // Hide Status Bar and Navigation Bar (Immersive Mode)
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  final configService = JsonConfigService();
  final appInitializer = AppInitializer(configProvider: configService);
  final initializationResult = await appInitializer.initialize();

  runApp(
    OpenPhotoFrameApp(
      configProvider: configService,
      initialConfigLoadResult: initializationResult.configLoadResult,
    ),
  );
}

class OpenPhotoFrameApp extends StatelessWidget {
  final JsonConfigService configProvider;
  final ConfigLoadResult initialConfigLoadResult;

  const OpenPhotoFrameApp({
    super.key,
    required this.configProvider,
    this.initialConfigLoadResult = const ConfigLoadResult.clean(),
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // 1. Infrastructure Services (Singletons)
        ChangeNotifierProvider<ConfigProvider>.value(value: configProvider),
        ProxyProvider<ConfigProvider, StorageProvider>(
          update: (_, config, previous) => 
              previous ?? LocalStorageProvider(configProvider: config),
          dispose: (_, storage) => (storage as LocalStorageProvider).dispose(),
        ),
        Provider<MetadataProvider>(
          create: (_) => ExifMetadataProvider(),
        ),
        Provider<PlaylistStrategy>(
          create: (_) => WeightedFreshnessStrategy(),
        ),
        Provider<DisplayController>(
          create: (_) => NativeDisplayController(),
          dispose: (_, controller) => controller.dispose(),
        ),
        
        // Repository needs Storage, Metadata, and Config - REUSE existing instance
        ProxyProvider3<StorageProvider, MetadataProvider, ConfigProvider, PhotoRepository>(
          update: (_, storage, metadata, config, previous) => 
              previous ?? HybridPhotoRepository(
                storageProvider: storage,
                metadataProvider: metadata,
                configProvider: config,
              ),
          dispose: (_, repo) => repo.dispose(),
        ),
        
        // 2. Application Services (Dependent on Infrastructure)
        // Note: SyncProvider is created dynamically via factory to pick up config changes
        // REUSE existing PhotoService instance
        ChangeNotifierProvider<PhotoService>(
          create: (context) {
            final storage = context.read<StorageProvider>();
            final playlist = context.read<PlaylistStrategy>();
            final repo = context.read<PhotoRepository>();
            final config = context.read<ConfigProvider>();

            // Factory function that creates a SyncProvider with current config
            SyncProvider createSyncProvider() {
              final type = config.activeSourceType;
              final sourceConfig = config.getSourceConfig(type);

              if (type == 'nextcloud_link') {
                final webdavConfig = WebDavSourceConfig.fromMap(sourceConfig);
                if (webdavConfig.url.isNotEmpty) {
                  return WebDavSyncService.fromConfig(webdavConfig, storage);
                }
              } else if (type == 'icloud_album') {
                final icloudConfig = ICloudAlbumSourceConfig.fromMap(sourceConfig);
                if (icloudConfig.isValid) {
                  return ICloudAlbumSyncService(
                    config: icloudConfig,
                    storageProvider: storage,
                    timeoutSeconds: config.syncTimeoutSeconds,
                  );
                }
              }

              return NoOpSyncService();
            }

            return PhotoService(
              syncProviderFactory: createSyncProvider,
              playlistStrategy: playlist,
              repository: repo,
              configProvider: config,
              storageProvider: storage,
            );
          },
        ),

        // Web settings UI — accessible from any browser on the LAN at port 8080
        Provider<WebServerService>(
          lazy: false,
          create: (context) {
            final service = WebServerService(
              configProvider: context.read<ConfigProvider>(),
              photoService: context.read<PhotoService>(),
              storageProvider: context.read<StorageProvider>(),
            );
            service.start();
            return service;
          },
          dispose: (_, service) => service.stop(),
        ),

        // Opt-in GitHub self-updater (no-op unless enabled in settings)
        ChangeNotifierProvider<UpdateService>(
          lazy: false,
          create: (context) {
            final service = UpdateService(
              configProvider: context.read<ConfigProvider>(),
            );
            service.onUpdateAvailable = (info) {
              final navContext = appNavigatorKey.currentContext;
              if (navContext != null) {
                showUpdateDialog(navContext, info, service);
              }
            };
            service.start();
            return service;
          },
        ),
      ],
      child: MaterialApp(
        navigatorKey: appNavigatorKey,
        title: 'OpenPhotoFrame',
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('en'),
          Locale('de'),
        ],
        themeMode: ThemeMode.dark,
        darkTheme: ThemeData(
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.deepPurple,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
          scaffoldBackgroundColor: Colors.black,
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
          ),
        ),
        theme: ThemeData(
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.deepPurple,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
          scaffoldBackgroundColor: Colors.black,
        ),
        home: SlideshowScreen(
          initialConfigLoadResult: initialConfigLoadResult,
        ),
      ),
    );
  }
}
