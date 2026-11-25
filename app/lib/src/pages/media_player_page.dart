import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:filemanager/l10n/app_localizations.dart';
import '../dialogs/file_picker_dialog.dart';
import '../rust/api/servers.dart';
import '../services/global_playback_service.dart';
import '../services/path_utils.dart';
import '../services/preferences_service.dart';
import '../services/subtitle_service.dart';
import '../services/vault_service.dart';
import '../widgets/app_swipe_back.dart';
import '../widgets/media_player/media_player_controls.dart';
import '../widgets/media_player/media_player_hud.dart';
import '../widgets/media_player/media_player_shared.dart';
import 'native_media_player_page.dart';

/// Video and audio playback for local, remote, and archive files.
///
/// Native files are opened directly. Anything else is served over a loopback
/// HTTP endpoint with Range support, so seeking works without downloading the
/// whole file first.
/// One playable item in a [MediaPlayerPage] session. All tracks share
/// the page's root; only the path differs.
class MediaTrack {
  final String path;
  final String fileName;
  final bool isAudio;

  const MediaTrack({
    required this.path,
    required this.fileName,
    required this.isAudio,
  });
}

class MediaPlayerPage extends StatelessWidget {
  final String root;
  final String path;
  final String fileName;
  final bool isAudio;

  /// Sibling media files from the folder the user opened, in display
  /// order. Empty means single-file playback (the fields above).
  final List<MediaTrack> playlist;
  final int startIndex;
  final bool forceMediaKit;

  const MediaPlayerPage({
    super.key,
    required this.root,
    required this.path,
    required this.fileName,
    required this.isAudio,
    this.playlist = const [],
    this.startIndex = 0,
    this.forceMediaKit = false,
  });

  /// Check whether the file extension is natively supported by Apple AVPlayer.
  static bool isAppleNativeFormat(String fileNameOrPath) {
    final dot = fileNameOrPath.lastIndexOf('.');
    if (dot < 0) return false;
    final ext = fileNameOrPath.substring(dot + 1).toLowerCase();
    return const {
      'mp4', 'm4v', 'mov', 'qt', 'm3u8', 'mp3', 'm4a', 'aac', 'wav',
    }.contains(ext);
  }

  @override
  Widget build(BuildContext context) {
    if (Platform.isIOS && !forceMediaKit) {
      // On iOS, use NativeMediaPlayerPage (AVPlayer) for Apple native formats.
      // For all non-native formats (MKV, AVI, WebM, FLV, WMV, RMVB, TS, etc.),
      // route to _MediaKitPlayerPage (libmpv), keeping iOS format support 100%
      // consistent with all other platforms.
      if (isAppleNativeFormat(path)) {
        return NativeMediaPlayerPage(
          root: root,
          path: path,
          fileName: fileName,
          isAudio: isAudio,
          playlist: playlist,
          startIndex: startIndex,
        );
      }
    }
    return _MediaKitPlayerPage(
      root: root,
      path: path,
      fileName: fileName,
      isAudio: isAudio,
      playlist: playlist,
      startIndex: startIndex,
    );
  }
}

class _MediaKitPlayerPage extends StatefulWidget {
  final String root;
  final String path;
  final String fileName;
  final bool isAudio;
  final List<MediaTrack> playlist;
  final int startIndex;

  const _MediaKitPlayerPage({
    required this.root,
    required this.path,
    required this.fileName,
    required this.isAudio,
    this.playlist = const [],
    this.startIndex = 0,
  });

  @override
  State<_MediaKitPlayerPage> createState() => _MediaKitPlayerPageState();
}

class _MediaKitPlayerPageState extends State<_MediaKitPlayerPage> {
  final GlobalKey<VideoState> _videoKey = GlobalKey<VideoState>();
  late final Player _player;
  late final VideoController _controller;
  StreamSubscription<String>? _errorSub;
  StreamSubscription<double>? _volumeSub;
  StreamSubscription<bool>? _playingSub;
  String? _error;
  bool _opened = false;
  bool _startedStream = false;
  bool _isLooping = false;
  static const _prefVolume = 'player.volume';
  static const _prefLoop = 'player.loop';
  static const _prefAutoNext = 'player.auto_next';
  static const _prefResumePrefix = 'player.resume.';
  late int _index;
  bool _switching = false;
  int _openGeneration = 0;
  int _eofRetries = 0;
  bool _autoNext = true;
  StreamSubscription<bool>? _completedSub;

  MediaTrack get _track => widget.playlist.isEmpty
      ? MediaTrack(path: widget.path, fileName: widget.fileName, isAudio: widget.isAudio)
      : widget.playlist[_index.clamp(0, widget.playlist.length - 1)];
  bool get _hasPrev => widget.playlist.length > 1 && _index > 0;
  bool get _hasNext =>
      widget.playlist.length > 1 && _index < widget.playlist.length - 1;

  /// Where playback was when the page closed, keyed by the opened file.
  String get _resumeKey => '$_prefResumePrefix${widget.root}|${_track.path}';
  bool _resumeApplied = false;
  Duration? _retryPosition;
  StreamSubscription<Duration>? _resumeSub;
  double _volume = 100.0;
  double _lastNonZeroVolume = 100.0;

  double _playbackSpeed = 1.0;
  bool _isExplicitlyClosed = false;
  Timer? _speedHudTimer;
  double? _hudSpeed;
  StreamSubscription<double>? _rateSub;

  bool _isSpeedBoosting = false;
  double _preBoostSpeed = 1.0;
  double _boostRate = 2.0;

  BoxFit _videoFit = BoxFit.contain;
  bool _vaultAutoClosing = false;

  void _onVaultChanged() {
    final vid = vaultIdFromRoot(widget.root);
    if (vid == null || VaultService.instance.isUnlocked(vid)) return;
    if (!_isExplicitlyClosed) {
      _isExplicitlyClosed = true;
      final ownedByService =
          identical(GlobalPlaybackService.instance.desktopPlayer, _player);
      final streamOwnedByService = GlobalPlaybackService.instance.startedStream;
      _player.stop();
      GlobalPlaybackService.instance.stop();
      if (!ownedByService) {
        _player.dispose();
      }
      if (_startedStream && !streamOwnedByService) {
        _startedStream = false;
        stopMediaStreams();
      }
    }
    if (!_vaultAutoClosing && mounted) {
      _vaultAutoClosing = true;
      final route = ModalRoute.of(context);
      if (route != null && route.isActive && !route.isFirst) {
        Navigator.of(context).removeRoute(route);
      } else if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    }
  }

  void _cycleVideoFit() {
    HapticFeedback.lightImpact();
    setState(() {
      _videoFit = nextPlayerVideoFit(_videoFit);
    });
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.videoFitChanged(playerVideoFitLabel(l10n, _videoFit))),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _showAudioTrackDialog() {
    final l10n = AppLocalizations.of(context);
    final realTracks = _player.state.tracks.audio
        .where((t) => t.id != 'auto' && t.id != 'no')
        .toList();
    final current = _player.state.track.audio;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Text(
                l10n.audioTracksTitle(realTracks.length),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            const Divider(),
            if (realTracks.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(l10n.noAudioTracks, style: const TextStyle(color: Colors.grey)),
              )
            else ...[
              ListTile(
                leading: Icon(
                  current == AudioTrack.auto() ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: current == AudioTrack.auto() ? Colors.blueAccent : null,
                ),
                title: Text(l10n.audioTrackDefault),
                onTap: () {
                  _player.setAudioTrack(AudioTrack.auto());
                  Navigator.of(ctx).pop();
                  HapticFeedback.lightImpact();
                },
              ),
              for (final t in realTracks) ...[
                Builder(
                  builder: (_) {
                    final rawTitle = t.title?.trim();
                    final rawLang = t.language?.trim();
                    final displayTitle = (rawTitle != null && rawTitle.isNotEmpty)
                        ? rawTitle
                        : ((rawLang != null && rawLang.isNotEmpty)
                            ? rawLang
                            : l10n.audioTrackItem(t.id));
                    final showSubtitle = rawTitle != null &&
                        rawTitle.isNotEmpty &&
                        rawLang != null &&
                        rawLang.isNotEmpty &&
                        rawLang != rawTitle;
                    return ListTile(
                      leading: Icon(
                        t == current ? Icons.radio_button_checked : Icons.radio_button_off,
                        color: t == current ? Colors.blueAccent : null,
                      ),
                      title: Text(displayTitle),
                      subtitle: showSubtitle ? Text(rawLang) : null,
                      onTap: () {
                        _player.setAudioTrack(t);
                        Navigator.of(ctx).pop();
                        HapticFeedback.lightImpact();
                      },
                    );
                  },
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  void _showSubtitleTrackDialog() {
    final l10n = AppLocalizations.of(context);
    final realTracks = _player.state.tracks.subtitle
        .where((t) => t.id != 'auto' && t.id != 'no')
        .toList();
    final current = _player.state.track.subtitle;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Text(
                l10n.subtitleTracksTitle(realTracks.length),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.folder_open_outlined),
              title: Text(l10n.loadExternalSubtitle),
              onTap: () async {
                Navigator.of(ctx).pop();
                await _pickExternalSubtitle();
              },
            ),
            ListTile(
              leading: Icon(
                current == SubtitleTrack.no() ? Icons.radio_button_checked : Icons.radio_button_off,
                color: current == SubtitleTrack.no() ? Colors.blueAccent : null,
              ),
              title: Text(l10n.subtitlesOff),
              onTap: () {
                _player.setSubtitleTrack(SubtitleTrack.no());
                Navigator.of(ctx).pop();
                HapticFeedback.lightImpact();
              },
            ),
            for (final t in realTracks)
              Builder(
                builder: (_) {
                  final rawTitle = t.title?.trim();
                  final rawLang = t.language?.trim();
                  final displayTitle = (rawTitle != null && rawTitle.isNotEmpty)
                      ? rawTitle
                      : ((rawLang != null && rawLang.isNotEmpty)
                          ? rawLang
                          : l10n.subtitleTrackItem(t.id));
                  final showSubtitle = rawTitle != null &&
                      rawTitle.isNotEmpty &&
                      rawLang != null &&
                      rawLang.isNotEmpty &&
                      rawLang != rawTitle;
                  return ListTile(
                    leading: Icon(
                      t == current ? Icons.radio_button_checked : Icons.radio_button_off,
                      color: t == current ? Colors.blueAccent : null,
                    ),
                    title: Text(displayTitle),
                    subtitle: showSubtitle ? Text(rawLang) : null,
                    onTap: () {
                      _player.setSubtitleTrack(t);
                      Navigator.of(ctx).pop();
                      HapticFeedback.lightImpact();
                    },
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showSleepTimerDialog() {
    showPlayerSleepTimerSheet(
      context,
      onEndOfTrackSelected: () {
        if (_isLooping) {
          _isLooping = false;
          _player.setPlaylistMode(PlaylistMode.none);
          PreferencesService.instance.setBool(_prefLoop, false);
        }
      },
      onChanged: () {
        if (mounted) setState(() {});
      },
    );
  }

  void _onLongPressStart(LongPressStartDetails details) {
    if (!_player.state.playing) return;
    HapticFeedback.mediumImpact();
    _preBoostSpeed = _playbackSpeed;
    _boostRate = _preBoostSpeed >= 2.0 ? 3.0 : 2.0;
    _player.setRate(_boostRate);
    setState(() {
      _isSpeedBoosting = true;
    });
  }

  void _onLongPressEnd(LongPressEndDetails details) {
    if (!_isSpeedBoosting) return;
    HapticFeedback.lightImpact();
    _player.setRate(_preBoostSpeed);
    setState(() {
      _isSpeedBoosting = false;
    });
  }

  void _onLongPressCancel() {
    if (!_isSpeedBoosting) return;
    _player.setRate(_preBoostSpeed);
    if (mounted) {
      setState(() {
        _isSpeedBoosting = false;
      });
    }
  }

  void _setSpeed(double speed) {
    _isSpeedBoosting = false;
    _playbackSpeed = speed;
    _player.setRate(speed);
    savePlaybackSpeed(speed);
    GlobalPlaybackService.instance.setPlaybackSpeed(speed);
    _showSpeedHud(speed);
    if (mounted) setState(() {});
  }

  void _showSpeedHud(double speed) {
    _speedHudTimer?.cancel();
    setState(() {
      _hudSpeed = speed;
    });
    _speedHudTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() {
          _hudSpeed = null;
        });
      }
    });
  }

  void _cycleSpeed({required bool increase}) {
    _setSpeed(nextPlaybackSpeed(_playbackSpeed, increase: increase));
  }

  @override
  void initState() {
    super.initState();
    VaultService.instance.addListener(_onVaultChanged);
    // Must be set before any _track access: _track indexes the playlist.
    _index = widget.playlist.isEmpty
        ? 0
        : widget.startIndex.clamp(0, widget.playlist.length - 1);
    final session = GlobalPlaybackService.instance;
    final restored = session.hasActiveSession &&
        session.currentRoot == widget.root &&
        session.currentPath == _track.path &&
        session.desktopPlayer != null &&
        session.desktopVideoController != null;
    if (restored) {
      _player = session.desktopPlayer!;
      _controller = session.desktopVideoController!;
      _startedStream = session.startedStream;
      _opened = true;
      session.setFullScreen(true);
    } else {
      if (session.hasActiveSession) {
        session.stop();
      }
      _player = Player(
        configuration: PlayerConfiguration(
          bufferSize: PreferencesService.instance.bufferSizeMb * 1024 * 1024,
        ),
      );
      _tunePlayerProperties();
      _controller = VideoController(
        _player,
        configuration: const VideoControllerConfiguration(
          hwdec: 'auto-safe',
          enableHardwareAcceleration: true,
        ),
      );
    }
    _volume = _player.state.volume;
    _playbackSpeed = _player.state.rate;
    _playingSub = _player.stream.playing.listen((playing) {
      if (playing) {
        WakelockPlus.enable().catchError((_) {});
      } else {
        WakelockPlus.disable().catchError((_) {});
      }
    });
    if (!restored) {
      final savedSpeed = loadSavedPlaybackSpeed();
      if (savedSpeed != 1.0) {
        _playbackSpeed = savedSpeed;
        _player.setRate(savedSpeed);
      }
      // Volume is a user preference, so a muted-then-closed player does not come
      // back silent next time.
      final savedVolume = double.tryParse(
        PreferencesService.instance.getString(_prefVolume) ?? '',
      );
      if (savedVolume != null) {
        _volume = savedVolume.clamp(0.0, 100.0);
        _player.setVolume(_volume);
      }
    }
    _rateSub = _player.stream.rate.listen((rate) {
      if (mounted && !_isSpeedBoosting && _playbackSpeed != rate) {
        setState(() => _playbackSpeed = rate);
      }
    });
    // Loop is a preference too: someone who loops one clip usually keeps
    // looping the next one.
    _isLooping = PreferencesService.instance.getBool(_prefLoop) ?? false;
    if (!restored && _isLooping) _player.setPlaylistMode(PlaylistMode.single);
    _autoNext = PreferencesService.instance.getBool(_prefAutoNext) ?? true;
    _volumeSub = _player.stream.volume.listen((vol) {
      if (mounted) setState(() => _volume = vol);
    });
    _errorSub = _player.stream.error.listen((message) {
      if (mounted) setState(() => _error = message);
    });
    _completedSub = _player.stream.completed.listen((completed) {
      if (completed) {
        final pos = _player.state.position;
        final dur = _player.state.duration;
        // Premature stream termination (>2s before true duration):
        // auto-resume from current position instead of pausing or skipping.
        // Capped: a file with inflated duration metadata would otherwise
        // stop→open→seek at the same spot forever.
        if (dur > const Duration(seconds: 3) &&
            pos < dur - const Duration(seconds: 2)) {
          if (_eofRetries < 2) {
            _eofRetries++;
            _retry(fromPosition: pos);
          }
          return;
        }
        _eofRetries = 0;
        if (GlobalPlaybackService.instance.consumeEndOfTrackSleepTimer()) {
          if (_isLooping) {
            _isLooping = false;
            _player.setPlaylistMode(PlaylistMode.none);
            PreferencesService.instance.setBool(_prefLoop, false);
            if (mounted) setState(() {});
          }
          _player.pause();
          return;
        }
        // Auto-advance only on a natural finish: not while looping a
        // single track and not while a manual track switch is mid-open.
        if (_autoNext && completed && !_isLooping && !_switching && _hasNext) {
          final nextTrack = widget.playlist[_index + 1];
          _openTrack(_index + 1);
          if (mounted) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(AppLocalizations.of(context).autoPlayingNext(nextTrack.fileName)),
                duration: const Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      }
    });
    if (!_opened) {
      _open();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final l10n = AppLocalizations.of(context);
    GlobalPlaybackService.instance.setPrivacyMediaLabels(
      audio: l10n.privacyMediaAudio,
      video: l10n.privacyMediaVideo,
    );
  }

  /// Switches playback to another track in the playlist, saving the
  /// outgoing track's resume position first.
  Future<void> _openTrack(int index) async {
    if (index < 0 || index >= widget.playlist.length) return;
    _saveResumePosition();
    _resumeSub?.cancel();
    _resumeSub = null;
    _resumeApplied = false;
    _switching = true;
    _eofRetries = 0;
    setState(() {
      _index = index;
      _error = null;
      _opened = false;
    });
    try {
      await _open();
    } finally {
      if (index == _index) _switching = false;
    }
  }

  void _showPlaylist() {
    showMediaPlaylistSheet(
      context,
      playlist: widget.playlist,
      currentIndex: _index,
      onSelectTrack: _openTrack,
    );
  }

  void _toggleMute() {
    if (_volume > 0) {
      _lastNonZeroVolume = _volume;
      _player.setVolume(0.0);
    } else {
      _player.setVolume(_lastNonZeroVolume > 0 ? _lastNonZeroVolume : 100.0);
    }
    _saveVolume();
  }

  void _changeVolume(double delta) {
    final newVol = (_volume + delta).clamp(0.0, 100.0);
    _player.setVolume(newVol);
    if (newVol > 0) _lastNonZeroVolume = newVol;
    // _volume is updated by the stream listener a tick later; persist the
    // value we just set or the last adjustment is lost.
    _saveVolume(newVol);
  }

  /// Remember the level the user settled on; a muted session should not
  /// silence the next video.
  void _saveVolume([double? level]) {
    final current = level ?? _volume;
    final saved = current > 0 ? current : _lastNonZeroVolume;
    PreferencesService.instance.setString(_prefVolume, saved.toStringAsFixed(0));
  }

  void _seekRelative(int seconds) {
    final duration = _player.state.duration;
    final pos = _player.state.position + Duration(seconds: seconds);
    final target = pos < Duration.zero
        ? Duration.zero
        : (duration > Duration.zero && pos > duration ? duration : pos);
    _player.seek(target);
  }


  Future<void> _open() async {
    final generation = ++_openGeneration;
    final track = _track;
    final index = _index;
    final resumeKey = _resumeKey;
    try {
      final String uri;
      final native = joinNative(widget.root, track.path);
      if (isNativeRoot(widget.root) && File(native).existsSync()) {
        uri = Uri.file(native).toString();
      } else {
        final base = (await startMediaStream(root: widget.root))
            .replaceFirst(RegExp(r'/$'), '');
        _startedStream = true;
        final encoded = track.path
            .split('/')
            .where((segment) => segment.isNotEmpty)
            .map(Uri.encodeComponent)
            .join('/');
        final bufferMb = PreferencesService.instance.bufferSizeMb;
        uri = '$base/$encoded?buffer_mb=$bufferMb';
      }
      await _tunePlayerProperties();
      await _player.open(Media(uri));
      // A newer open superseded this one while awaiting; touching session
      // state now would attach metadata/resume to the wrong track.
      if (generation != _openGeneration) return;
      GlobalPlaybackService.instance.setDesktopSession(
        root: widget.root,
        path: track.path,
        fileName: track.fileName,
        isAudio: track.isAudio,
        playlist: widget.playlist,
        currentIndex: index,
        player: _player,
        controller: _controller,
        startedStream: _startedStream,
        playbackSpeed: _playbackSpeed,
      );
      await _tunePlayerProperties();
      if (generation != _openGeneration) return;
      if (_playbackSpeed != 1.0) {
        await _player.setRate(_playbackSpeed);
      }
      if (mounted) setState(() => _opened = true);
      if (!_track.isAudio) {
        unawaited(_autoLoadExternalSubtitle(generation));
      }
      if (_retryPosition != null) {
        final resumePos = _retryPosition!;
        _retryPosition = null;
        _resumeApplied = true;
        _player.seek(resumePos);
      } else {
        _applyResume(resumeKey);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  /// Continues where the file was left off, unless it was near the start or
  /// already finished. Audio books and long videos are the reason this exists.
  ///
  /// The duration is often still unknown right after `open`, so the seek waits
  /// for the first non-zero duration before deciding whether the saved spot is
  /// past the end.
  Future<void> _autoLoadExternalSubtitle(int generation) async {
    try {
      final loaded = await SubtitleService.findMatchingSubtitle(
        root: widget.root,
        mediaPath: _track.path,
      );
      if (loaded == null || !mounted || generation != _openGeneration) return;
      await _player.setSubtitleTrack(
        SubtitleTrack.data(loaded.rawContent, title: loaded.name),
      );
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.subtitleAutoLoaded(loaded.name)),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (_) {}
  }

  Future<void> _pickExternalSubtitle() async {
    final l10n = AppLocalizations.of(context);
    final slash = _track.path.lastIndexOf('/');
    final dir = slash >= 0 ? _track.path.substring(0, slash) : '';
    final picked = await FilePickerDialog.show(
      context,
      title: l10n.loadExternalSubtitle,
      initialRoot: widget.root,
      initialPath: dir,
    );
    if (picked == null || picked.paths.isEmpty || !mounted) return;
    final subPath = picked.paths.first;
    final subName = subPath.split('/').last;
    try {
      final loaded = await SubtitleService.loadFromVfs(
        root: picked.root,
        path: subPath,
        name: subName,
      );
      if (!mounted) return;
      if (loaded == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.subtitleLoadFailed)),
        );
        return;
      }
      await _player.setSubtitleTrack(
        SubtitleTrack.data(loaded.rawContent, title: loaded.name),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.subtitleAutoLoaded(loaded.name))),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.subtitleLoadFailed)),
        );
      }
    }
  }

  void _applyResume([String? key]) {
    if (vaultIdFromRoot(widget.root) != null) return;
    if (_resumeApplied) return;
    _resumeApplied = true;
    final saved = int.tryParse(
      PreferencesService.instance.getString(key ?? _resumeKey) ?? '',
    );
    if (saved == null || saved < 5000) return;
    _resumeSub = _player.stream.duration.listen((duration) {
      if (duration <= Duration.zero) return;
      _resumeSub?.cancel();
      _resumeSub = null;
      if (saved > duration.inMilliseconds * 0.95) return;
      _player.seek(Duration(milliseconds: saved));
    });
  }

  void _saveResumePosition() {
    if (vaultIdFromRoot(widget.root) != null) return;
    final position = _player.state.position;
    final duration = _player.state.duration;
    if (duration <= Duration.zero) return;
    if (position < const Duration(seconds: 5) ||
        position > duration * 0.95) {
      PreferencesService.instance.remove(_resumeKey);
      return;
    }
    PreferencesService.instance.setString(
      _resumeKey,
      position.inMilliseconds.toString(),
    );
  }

  /// Reopens the same source after a playback error, e.g. once the network
  /// is back or the remote stream endpoint has restarted.
  Future<void> _retry({Duration? fromPosition}) async {
    _resumeApplied = false;
    _retryPosition = fromPosition;
    await _player.stop();
    if (mounted) {
      setState(() {
        _error = null;
        _opened = false;
      });
    }
    await _open();
  }

  Future<void> _tunePlayerProperties() async {
    final dynamic platform = _player.platform;
    if (platform != null) {
      final bufferSec = PreferencesService.instance.bufferDurationSec.toString();
      final bufferMb = PreferencesService.instance.bufferSizeMb;
      final maxBytes = '${bufferMb * 1024 * 1024}';
      final maxBackBytes = '${(bufferMb ~/ 2) * 1024 * 1024}';
      try {
        final futures = <Future<dynamic>>[
          platform.setProperty('cache-pause', 'no') as Future<dynamic>,
          platform.setProperty('cache-pause-wait', '0') as Future<dynamic>,
          platform.setProperty('cache-pause-initial', 'no') as Future<dynamic>,
          platform.setProperty('cache-on-disk', 'no') as Future<dynamic>,
          // Use 'audio' clock sync mode so high playback rates (4x, 8x) advance
          // smoothly without audio resampler overflow or massive vo frame drops.
          platform.setProperty('video-sync', 'audio') as Future<dynamic>,
          // Increase scaletempo2 ceiling beyond the default 8.0 to handle 8x/16x
          // smoothly without muting or dropping audio.
          platform.setProperty('af', 'scaletempo2=max-speed=16:search-interval=30') as Future<dynamic>,
          platform.setProperty('demuxer-readahead-secs', bufferSec) as Future<dynamic>,
          platform.setProperty('demuxer-max-bytes', maxBytes) as Future<dynamic>,
          platform.setProperty('demuxer-max-back-bytes', maxBackBytes) as Future<dynamic>,
          platform.setProperty('network-timeout', '60') as Future<dynamic>,
          platform.setProperty('framedrop', 'vo') as Future<dynamic>,
          platform.setProperty('hr-seek-framedrop', 'yes') as Future<dynamic>,
          platform.setProperty('audio-buffer', '1.0') as Future<dynamic>,
          platform.setProperty('keep-open-pause', 'no') as Future<dynamic>,
        ];
        await Future.wait(futures);
      } catch (_) {}
    }
  }

  void _closeAndExit() {
    _isExplicitlyClosed = true;
    _saveResumePosition();
    final ownedByService =
        identical(GlobalPlaybackService.instance.desktopPlayer, _player);
    final streamOwnedByService = GlobalPlaybackService.instance.startedStream;
    _player.stop();
    GlobalPlaybackService.instance.stop();
    if (!ownedByService) {
      _player.dispose();
    }
    if (_startedStream && !streamOwnedByService) {
      _startedStream = false;
      stopMediaStreams();
    }
    if (mounted) {
      Navigator.of(context).maybePop();
    }
  }

  @override
  void dispose() {
    VaultService.instance.removeListener(_onVaultChanged);
    WakelockPlus.disable().catchError((_) {});
    _playingSub?.cancel();
    _rateSub?.cancel();
    _speedHudTimer?.cancel();
    if (!_isExplicitlyClosed) {
      _saveResumePosition();
    }
    _resumeSub?.cancel();
    _completedSub?.cancel();
    _errorSub?.cancel();
    _volumeSub?.cancel();

    // _closeAndExit() already stopped playback, and GlobalPlaybackService.stop()
    // owns disposing the Player. Disposing it again here frees the libmpv handle
    // twice and segfaults the mpv core thread, so the closed path is a no-op.
    if (!_isExplicitlyClosed) {
      if (GlobalPlaybackService.instance.hasActiveSession) {
        GlobalPlaybackService.instance.setFullScreen(false);
      } else {
        _player.stop();
        _player.dispose();
        if (_startedStream) {
          // The loopback stream server started for this root would otherwise
          // keep running (and holding its port) for the rest of the app's
          // lifetime, accumulating one server per played remote file.
          stopMediaStreams();
        }
        GlobalPlaybackService.instance.stop();
      }
    }
    super.dispose();
  }

  /// The bundled controls already seek; they just lack a rate menu. Both
  /// themes are installed because `AdaptiveVideoControls` picks one by
  /// platform, and fullscreen inherits whichever was active.
  Widget _withSpeedControls(Widget child) {
    // Each theme data gets its own instance: normal and fullscreen controls can
    // be mounted at the same time, and one widget instance cannot be.
    Widget speedButton() => _SpeedButton(
          player: _player,
          currentRate: _playbackSpeed,
          onSelected: _setSpeed,
        );
    Widget nextButton() => widget.playlist.length > 1
        ? IconButton(
            icon: Icon(
              Icons.skip_next,
              color: _hasNext ? Colors.white : Colors.white38,
            ),
            tooltip: AppLocalizations.of(context).nextEpisodeShortcut,
            onPressed: _hasNext ? () => _openTrack(_index + 1) : null,
          )
        : const SizedBox.shrink();
    final mobileNormal = kDefaultMaterialVideoControlsThemeData.copyWith(
      // Not enabled by default in non-fullscreen. The page used to wrap the
      // video in its own drag handler, but the controls' recognizer is deeper
      // in the tree and always won the gesture arena, so it never fired.
      seekGesture: true,
      volumeGesture: true,
      brightnessGesture: true,
      seekOnDoubleTap: true,
      seekOnDoubleTapEnabledWhileControlsVisible: true,
      bottomButtonBarMargin: const EdgeInsets.only(
        left: 16.0,
        right: 8.0,
        bottom: 24.0,
      ),
      seekBarMargin: const EdgeInsets.only(
        left: 16.0,
        right: 16.0,
        bottom: 84.0,
      ),
      bottomButtonBar: [
        ...kDefaultMaterialVideoControlsThemeData.bottomButtonBar,
        nextButton(),
        speedButton(),
      ],
    );
    final mobileFullscreen = kDefaultMaterialVideoControlsThemeDataFullscreen
        .copyWith(
      seekGesture: true,
      volumeGesture: true,
      brightnessGesture: true,
      seekOnDoubleTap: true,
      seekOnDoubleTapEnabledWhileControlsVisible: true,
      bottomButtonBarMargin: const EdgeInsets.only(
        left: 16.0,
        right: 8.0,
        bottom: 36.0,
      ),
      seekBarMargin: const EdgeInsets.only(
        left: 16.0,
        right: 16.0,
        bottom: 96.0,
      ),
      bottomButtonBar: [
        ...kDefaultMaterialVideoControlsThemeDataFullscreen.bottomButtonBar,
        nextButton(),
        speedButton(),
      ],
    );
    final desktopNormal = kDefaultMaterialDesktopVideoControlsThemeData
        .copyWith(
      bottomButtonBar: [
        ...kDefaultMaterialDesktopVideoControlsThemeData.bottomButtonBar,
        nextButton(),
        speedButton(),
      ],
    );
    final desktopFullscreen = kDefaultMaterialDesktopVideoControlsThemeDataFullscreen
        .copyWith(
      bottomButtonBar: [
        ...kDefaultMaterialDesktopVideoControlsThemeDataFullscreen
            .bottomButtonBar,
        nextButton(),
        speedButton(),
      ],
    );

    return MaterialVideoControlsTheme(
      normal: mobileNormal,
      fullscreen: mobileFullscreen,
      child: MaterialDesktopVideoControlsTheme(
        normal: desktopNormal,
        fullscreen: desktopFullscreen,
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppSwipeBack(
      child: CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.space): () {
          _player.playOrPause();
        },
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () {
          _seekRelative(-5);
        },
        const SingleActivator(LogicalKeyboardKey.arrowRight): () {
          _seekRelative(5);
        },
        const SingleActivator(LogicalKeyboardKey.arrowUp): () {
          _changeVolume(10);
        },
        const SingleActivator(LogicalKeyboardKey.arrowDown): () {
          _changeVolume(-10);
        },
        const SingleActivator(LogicalKeyboardKey.keyM): () {
          _toggleMute();
        },
        const SingleActivator(LogicalKeyboardKey.keyF): () {
          _videoKey.currentState?.toggleFullscreen();
        },
        const SingleActivator(LogicalKeyboardKey.keyN): () {
          if (_hasNext) _openTrack(_index + 1);
        },
        const SingleActivator(LogicalKeyboardKey.keyP): () {
          if (_hasPrev) _openTrack(_index - 1);
        },
        const SingleActivator(LogicalKeyboardKey.keyJ): () => _seekRelative(-10),
        const SingleActivator(LogicalKeyboardKey.keyL): () => _seekRelative(10),
        const SingleActivator(LogicalKeyboardKey.keyK): () => _player.playOrPause(),
        const SingleActivator(LogicalKeyboardKey.bracketLeft): () {
          _cycleSpeed(increase: false);
        },
        const SingleActivator(LogicalKeyboardKey.bracketRight): () {
          _cycleSpeed(increase: true);
        },
        const SingleActivator(LogicalKeyboardKey.backslash): () {
          _setSpeed(1.0);
        },
      },
      child: Focus(
        autofocus: true,
        child: PopScope(
          canPop: true,
          onPopInvokedWithResult: (didPop, _) {
            if (!_isExplicitlyClosed) {
              _saveResumePosition();
            }
          },
          child: Theme(
            data: ThemeData.dark(),
            child: Scaffold(
              backgroundColor: Colors.black,
            appBar: AppBar(
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                tooltip: AppLocalizations.of(context).minimize,
                onPressed: () async {
                  _saveResumePosition();
                  if (context.mounted) {
                    Navigator.of(context).maybePop();
                  }
                },
              ),
              backgroundColor: Colors.black87,
              foregroundColor: Colors.white,
              iconTheme: const IconThemeData(color: Colors.white),
              actionsIconTheme: const IconThemeData(color: Colors.white),
              title: Text(_track.fileName, overflow: TextOverflow.ellipsis),
              actions: [
                if (widget.playlist.length > 1) ...[
                  IconButton(
                    icon: const Icon(Icons.queue_music),
                    tooltip: AppLocalizations.of(context).playlistProgress(_index + 1, widget.playlist.length),
                    onPressed: _showPlaylist,
                  ),
                  if (MediaQuery.sizeOf(context).width >= 600)
                    IconButton(
                      icon: Icon(_autoNext ? Icons.playlist_play : Icons.playlist_remove),
                      tooltip: _autoNext ? AppLocalizations.of(context).autoNextOn : AppLocalizations.of(context).autoNextOff,
                      color: _autoNext ? Colors.blueAccent : Colors.white60,
                      onPressed: () {
                        setState(() {
                          _autoNext = !_autoNext;
                          PreferencesService.instance.setBool(_prefAutoNext, _autoNext);
                        });
                      },
                    ),
                ],
                if (MediaQuery.sizeOf(context).width >= 600)
                  IconButton(
                    icon: Icon(_isLooping ? Icons.repeat_one : Icons.repeat),
                    tooltip: _isLooping ? AppLocalizations.of(context).loopSingle : AppLocalizations.of(context).loopOff,
                    color: _isLooping ? Colors.blueAccent : Colors.white,
                    onPressed: () {
                      setState(() {
                        _isLooping = !_isLooping;
                        _player.setPlaylistMode(
                          _isLooping ? PlaylistMode.single : PlaylistMode.none,
                        );
                        PreferencesService.instance.setBool(_prefLoop, _isLooping);
                      });
                    },
                  ),
                _SpeedButton(
                  player: _player,
                  currentRate: _playbackSpeed,
                  onSelected: _setSpeed,
                ),
                if (!_track.isAudio && MediaQuery.sizeOf(context).width >= 600)
                  IconButton(
                    icon: const Icon(Icons.aspect_ratio),
                    tooltip: AppLocalizations.of(context).videoFitLabel,
                    onPressed: _cycleVideoFit,
                  ),
                IconButton(
                  icon: const Icon(Icons.fullscreen),
                  tooltip: AppLocalizations.of(context).fullscreenShortcut,
                  onPressed: () {
                    _videoKey.currentState?.toggleFullscreen();
                  },
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  tooltip: AppLocalizations.of(context).playbackOptions,
                  onSelected: (action) {
                    switch (action) {
                      case 'prev':
                        if (_hasPrev) _openTrack(_index - 1);
                        break;
                      case 'next':
                        if (_hasNext) _openTrack(_index + 1);
                        break;
                      case 'loop':
                        setState(() {
                          _isLooping = !_isLooping;
                          _player.setPlaylistMode(
                            _isLooping ? PlaylistMode.single : PlaylistMode.none,
                          );
                          PreferencesService.instance.setBool(_prefLoop, _isLooping);
                        });
                        break;
                      case 'auto_next':
                        setState(() {
                          _autoNext = !_autoNext;
                          PreferencesService.instance.setBool(_prefAutoNext, _autoNext);
                        });
                        break;
                      case 'rewind':
                        _seekRelative(-10);
                        break;
                      case 'forward':
                        _seekRelative(10);
                        break;
                      case 'mute':
                        _toggleMute();
                        break;
                      case 'aspect_ratio':
                        _cycleVideoFit();
                        break;
                      case 'subtitles':
                        _showSubtitleTrackDialog();
                        break;
                      case 'audio_track':
                        _showAudioTrackDialog();
                        break;
                      case 'sleep_timer':
                        _showSleepTimerDialog();
                        break;
                    }
                  },
                  itemBuilder: (ctx) => [
                    PopupMenuItem(
                      value: 'loop',
                      child: Row(
                        children: [
                          Icon(
                            _isLooping ? Icons.repeat_one : Icons.repeat,
                            size: 20,
                            color: _isLooping ? Colors.blueAccent : null,
                          ),
                          const SizedBox(width: 10),
                          Text(_isLooping ? AppLocalizations.of(context).loopSingle : AppLocalizations.of(context).loopOff),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'mute',
                      child: Row(
                        children: [
                          Icon(
                            _volume == 0
                                ? Icons.volume_off
                                : (_volume < 50 ? Icons.volume_down : Icons.volume_up),
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Text(_volume == 0 ? AppLocalizations.of(context).unmuteShortcut : AppLocalizations.of(context).muteShortcut(_volume.toInt())),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'rewind',
                      child: Row(
                        children: [
                          Icon(Icons.replay_10, size: 20),
                          SizedBox(width: 10),
                          Text(AppLocalizations.of(context).rewind10s),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'forward',
                      child: Row(
                        children: [
                          Icon(Icons.forward_10, size: 20),
                          SizedBox(width: 10),
                          Text(AppLocalizations.of(context).forward10s),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(),
                    if (!_track.isAudio) ...[
                      PopupMenuItem(
                        value: 'aspect_ratio',
                        child: Row(
                          children: [
                            const Icon(Icons.aspect_ratio, size: 20),
                            const SizedBox(width: 10),
                            Text('${AppLocalizations.of(context).videoFitLabel} (${playerVideoFitLabel(AppLocalizations.of(context), _videoFit)})'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'subtitles',
                        child: Row(
                          children: [
                            const Icon(Icons.subtitles_outlined, size: 20),
                            const SizedBox(width: 10),
                            Text(AppLocalizations.of(context).subtitleTrackMenu),
                          ],
                        ),
                      ),
                    ],
                    PopupMenuItem(
                      value: 'audio_track',
                      child: Row(
                        children: [
                          const Icon(Icons.audiotrack_outlined, size: 20),
                          const SizedBox(width: 10),
                          Text(AppLocalizations.of(context).audioTrackMenu),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'sleep_timer',
                      child: Row(
                        children: [
                          const Icon(Icons.timer_outlined, size: 20),
                          const SizedBox(width: 10),
                          Text(sleepTimerMenuLabel(AppLocalizations.of(context))),
                        ],
                      ),
                    ),
                    if (widget.playlist.length > 1) ...[
                      const PopupMenuDivider(),
                      PopupMenuItem(
                        value: 'auto_next',
                        child: Row(
                          children: [
                            Icon(
                              _autoNext ? Icons.playlist_play : Icons.playlist_remove,
                              size: 20,
                              color: _autoNext ? Colors.blueAccent : null,
                            ),
                            const SizedBox(width: 10),
                            Text(_autoNext ? AppLocalizations.of(context).autoNextMenuOn : AppLocalizations.of(context).autoNextMenuOff),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'prev',
                        enabled: _hasPrev,
                        child: Row(
                          children: [
                            const Icon(Icons.skip_previous, size: 20),
                            const SizedBox(width: 10),
                            Text(AppLocalizations.of(context).previousShortcut),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'next',
                        enabled: _hasNext,
                        child: Row(
                          children: [
                            const Icon(Icons.skip_next, size: 20),
                            const SizedBox(width: 10),
                            Text(AppLocalizations.of(context).nextShortcut),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  tooltip: AppLocalizations.of(context).close,
                  onPressed: _closeAndExit,
                ),
              ],
            ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline,
                        size: 48, color: Colors.redAccent),
                    const SizedBox(height: 12),
                    Text(
                      AppLocalizations.of(context).cannotPlayFile,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(color: Colors.white),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 12, color: Colors.white70),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _retry,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: Text(AppLocalizations.of(context).retry),
                      style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white),
                    ),
                  ],
                ),
              ),
            )
          : !_opened
              ? const Center(child: CircularProgressIndicator())
              : Stack(
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onLongPressStart: _onLongPressStart,
                      onLongPressEnd: _onLongPressEnd,
                      onLongPressCancel: _onLongPressCancel,
                      child: _withSpeedControls(
                        Video(
                          key: _videoKey,
                          controller: _controller,
                          fit: _videoFit,
                          fill: Colors.black,
                          controls: AdaptiveVideoControls,
                          pauseUponEnteringBackgroundMode: false,
                          resumeUponEnteringForegroundMode: false,
                        ),
                      ),
                    ),
                    if (_isSpeedBoosting)
                      MediaPlayerSpeedBoostHud(boostRate: _boostRate),
                    if (_hudSpeed != null && !_isSpeedBoosting)
                      MediaPlayerSpeedToastHud(speed: _hudSpeed!),
                    if (_track.isAudio)
                      Positioned(
                        top: 24,
                        left: 0,
                        right: 0,
                        child: IgnorePointer(
                          child: Column(
                            children: [
                              Icon(Icons.audiotrack,
                                  size: 72,
                                  color: Colors.white.withValues(alpha: 0.25)),
                              const SizedBox(height: 8),
                              Text(
                                _track.fileName,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
          ),
          ),
        ),
      ),
    ),
    );
  }
}

/// Playback speed menu: 0.5× through 8×.
class _SpeedButton extends StatefulWidget {
  final Player player;
  final double currentRate;
  final ValueChanged<double>? onSelected;

  const _SpeedButton({
    required this.player,
    this.currentRate = 1.0,
    this.onSelected,
  });

  @override
  State<_SpeedButton> createState() => _SpeedButtonState();
}

class _SpeedButtonState extends State<_SpeedButton> {
  late double _rate;
  StreamSubscription<double>? _sub;

  @override
  void initState() {
    super.initState();
    _rate = loadSavedPlaybackSpeed(fallback: widget.currentRate);
    _sub = widget.player.stream.rate.listen((rate) {
      if (mounted && _rate != rate) setState(() => _rate = rate);
    });
  }

  @override
  void didUpdateWidget(covariant _SpeedButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentRate != widget.currentRate) {
      _rate = widget.currentRate;
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  String _label(double rate) {
    final text = rate == rate.roundToDouble()
        ? rate.toInt().toString()
        : rate.toString();
    return '$text×';
  }

  Future<void> _openMenu(BuildContext context) async {
    final player = widget.player;
    final onSelected = widget.onSelected;

    final selected = await showPlayerSpeedMenu(
      context: context,
      buttonContext: context,
      currentSpeed: _rate,
      rates: kMediaPlaybackSpeeds,
      onSelected: (rate) async {
        if (mounted) setState(() => _rate = rate);
        if (onSelected != null) {
          onSelected(rate);
        } else {
          await player.setRate(rate);
          savePlaybackSpeed(rate);
        }
      },
    );
    if (selected != null && mounted) {
      setState(() => _rate = selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: AppLocalizations.of(context).playbackSpeed,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: () => _openMenu(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white12,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              _label(_rate),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
