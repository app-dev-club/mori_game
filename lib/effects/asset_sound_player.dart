import 'asset_sound_player_stub.dart' show AssetSoundHandle;

import 'asset_sound_player_stub.dart'
    if (dart.library.io) 'asset_sound_player_io.dart'
    if (dart.library.js_interop) 'asset_sound_player_web.dart'
    if (dart.library.html) 'asset_sound_player_web.dart' as impl;

export 'asset_sound_player_stub.dart' show AssetSoundHandle;

Future<AssetSoundHandle?> playAssetSound(String assetPath) =>
    impl.playAssetSound(assetPath);
