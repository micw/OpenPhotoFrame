import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:provider/provider.dart';

import 'domain/interfaces/config_provider.dart';
import 'domain/interfaces/metadata_provider.dart';
import 'domain/interfaces/playlist_strategy.dart';
import 'domain/interfaces/sync_provider.dart';
import 'domain/interfaces/storage_provider.dart';
import 'domain/interfaces/photo_repository.dart';
import 'infrastructure/services/json_config_service.dart';
import 'infrastructure/services/file_metadata_provider.dart';
import 'infrastructure/services/nextcloud_sync_service.dart';
import 'infrastructure/services/noop_sync_service.dart';
import 'infrastructure/services/photo_service.dart';
import 'infrastructure/services/local_storage_provider.dart';
import 'infrastructure/repositories/file_system_photo_repository.dart';
import 'infrastructure/strategies/weighted_freshness_strategy.dart';
import 'ui/screens/slideshow_screen.dart';

void main() async {
  // Setup Logging
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    print('${record.level.name}: ${record.time}: ${record.message}');
  });

  WidgetsFlutterBinding.ensureInitialized();

  // Hide Status Bar and Navigation Bar (Immersive Mode)
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  // Load Config
  final configService = JsonConfigService();
  await configService.load();

  runApp(OpenPhotoFrameApp(configProvider: configService));
}

class OpenPhotoFrameApp extends StatelessWidget {
  final JsonConfigService configProvider;

  const OpenPhotoFrameApp({super.key, required this.configProvider});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // 1. Infrastructure Services (Singletons)
        ChangeNotifierProvider<ConfigProvider>.value(value: configProvider),
        Provider<StorageProvider>(
          create: (_) => LocalStorageProvider(),
        ),
        Provider<MetadataProvider>(
          create: (_) => FileMetadataProvider(),
        ),
        Provider<PlaylistStrategy>(
          create: (_) => WeightedFreshnessStrategy(),
        ),
        
        // Repository needs Storage and Metadata
        ProxyProvider2<StorageProvider, MetadataProvider, PhotoRepository>(
          update: (_, storage, metadata, __) => FileSystemPhotoRepository(
            storageProvider: storage,
            metadataProvider: metadata,
          ),
          dispose: (_, repo) => repo.dispose(),
        ),
        
        // 2. Application Services (Dependent on Infrastructure)
        // Note: SyncProvider is created dynamically via factory to pick up config changes
        ProxyProvider3<StorageProvider, PlaylistStrategy, PhotoRepository, PhotoService>(
          update: (context, storage, playlist, repo, __) {
            final config = context.read<ConfigProvider>();
            
            // Factory function that creates a SyncProvider with current config
            SyncProvider createSyncProvider() {
              final type = config.activeSourceType;
              final sourceConfig = config.getSourceConfig(type);

              if (type == 'nextcloud_link') {
                return NextcloudSyncService.fromPublicLink(
                  sourceConfig['url'] ?? '',
                  storage,
                );
              }
              
              return NoOpSyncService();
            }
            
            return PhotoService(
              syncProviderFactory: createSyncProvider,
              playlistStrategy: playlist,
              repository: repo,
              configProvider: config,
            );
          },
          dispose: (_, service) => service.dispose(),
        ),
      ],
      child: MaterialApp(
        title: 'OpenPhotoFrame',
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
        home: const SlideshowScreen(),
      ),
    );
  }
}
