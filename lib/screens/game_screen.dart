import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../services/firebase_service.dart';
import '../services/ad_service.dart';
import '../services/agora_service.dart';
import '../utils/app_theme.dart';
import '../widgets/color_palette_bar.dart';
import '../widgets/pixel_grid.dart';
import '../widgets/powerups_bar.dart';
import '../widgets/confetti_burst.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GameScreen extends StatefulWidget {
  final String roomId;
  final String playerId;
  final bool isHost;
  final bool isSolo;

  const GameScreen({
    super.key,
    required this.roomId,
    required this.playerId,
    required this.isHost,
    this.isSolo = false,
  });

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with TickerProviderStateMixin {
  Map<String, int> _gridData = {};
  Map<String, int> _cellStates = {};
  List<int> _palette = [];
  int _selectedColorIndex = -1;
  int _gridWidth = 0;
  int _gridHeight = 0;
  bool _isLoading = true;
  int _totalCells = 0;
  int _coloredCells = 0;
  bool _isCompleted = false;

  // Painting history for replay
  final List<_PaintStep> _paintHistory = [];
  int _myBrushStrokes = 0; // only count this player's strokes

  // Completed colors tracking
  Set<int> _completedColors = {};
  Map<int, int> _colorTotalCells = {}; // colorIndex -> total cells

  // For save to gallery
  final GlobalKey _gridRepaintKey = GlobalKey();

  // For gesture coordinate conversion
  final TransformationController _transformController = TransformationController();

  // Agora Voice
  final AgoraService _agoraService = AgoraService();
  bool _isMicMuted = false;
  int _remoteUserCount = 0;

  // Emoji Reactions
  int _lastReactionTimestamp = 0;
  final List<_ActiveEmoji> _floatingEmojis = [];

  // Sihirli Değnek
  int _wandCharges = 3;
  bool _isWandAnimating = false;

  // Güç Yükselticiler (başlangıç bonusu)
  int _hintCharges = 2;
  int _bombCharges = 1;
  int _fillCharges = 1;
  String? _hintCellKey; // highlighted cell for hint
  Timer? _hintTimer;

  // Konfeti
  bool _confettiActive = false;
  Color _confettiColor = Colors.purpleAccent;

  // Replay state
  bool _isReplaying = false;
  Map<String, int> _replayCellStates = {};
  int _replayStep = 0;
  Timer? _replayTimer;

  StreamSubscription? _roomSub;
  StreamSubscription? _cellAddSub;
  StreamSubscription? _cellChangeSub;

  late AnimationController _completionController;
  late Animation<double> _completionAnimation;

  @override
  void initState() {
    super.initState();
    _completionController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _completionAnimation = CurvedAnimation(
      parent: _completionController,
      curve: Curves.elasticOut,
    );
    _loadGameData();
    AdService.loadRewardedAd();
    _loadDailyBonus();
    if (!widget.isSolo) {
      _initVoiceChat();
    }
  }

  Future<void> _initVoiceChat() async {
    await _agoraService.initializeAndJoin(
      widget.roomId,
      onUserJoined: (uid) {
        if (mounted) setState(() => _remoteUserCount++);
      },
      onUserOffline: (uid) {
        if (mounted) {
          setState(() {
            _remoteUserCount = (_remoteUserCount > 0) ? _remoteUserCount - 1 : 0;
          });
        }
      },
    );
  }

  @override
  void dispose() {
    if (!widget.isSolo) {
      _agoraService.leaveChannel();
    }
    _roomSub?.cancel();
    _cellAddSub?.cancel();
    _cellChangeSub?.cancel();
    _completionController.dispose();
    _replayTimer?.cancel();
    _hintTimer?.cancel();
    _transformController.dispose();
    super.dispose();
  }

  Future<void> _loadGameData() async {
    _roomSub = FirebaseService.listenToRoom(widget.roomId, (room) {
      if (mounted) {
        setState(() {
          _palette = room.palette;
          _gridWidth = room.gridWidth;
          _gridHeight = room.gridHeight;
          _totalCells = room.totalCells;
          _buildColorTotals();
        });

        if (room.lastReaction != null) {
          final int ts = room.lastReaction!['timestamp'] ?? 0;
          if (ts > _lastReactionTimestamp) {
            // Sadece yeni atılanları animasyonla oynat (5 saniye içi)
            if (_lastReactionTimestamp != 0 || (DateTime.now().millisecondsSinceEpoch - ts < 5000)) {
              // Kendi attığımızı zaten lokal olarak trigger ettiğimiz için tekrar etmesini önleyebiliriz ama
              // senderId kontrolüyle bunu yapmak daha sağlıklı olur:
              if (room.lastReaction!['senderId'] != widget.playerId) {
                _triggerReaction(room.lastReaction!['emoji']);
              }
            }
            _lastReactionTimestamp = ts;
          }
        }
      }
    });

    _gridData = await FirebaseService.getGridData(widget.roomId);
    _cellStates = await FirebaseService.loadCellStates(widget.roomId);
    _coloredCells = _cellStates.length;
    _buildColorTotals();
    _updateCompletedColors();

    _cellAddSub = FirebaseService.listenToCellUpdates(
      widget.roomId,
      (cellKey, colorIndex, playerId) {
        if (mounted) {
          setState(() {
            if (!_cellStates.containsKey(cellKey)) {
              _cellStates[cellKey] = colorIndex;
              _coloredCells = _cellStates.length;
              // Track ALL players' strokes for replay & count
              _paintHistory.add(_PaintStep(cellKey: cellKey, colorIndex: colorIndex));
              if (playerId == widget.playerId) _myBrushStrokes++;
              _updateCompletedColors();
              _checkCompletion();
            }
          });
        }
      },
    );

    _cellChangeSub = FirebaseService.listenToCellChanges(
      widget.roomId,
      (cellKey, colorIndex, playerId) {
        if (mounted) {
          setState(() {
            _cellStates[cellKey] = colorIndex;
            _updateCompletedColors();
          });
        }
      },
    );

    setState(() => _isLoading = false);
  }

  void _buildColorTotals() {
    _colorTotalCells = {};
    for (final idx in _gridData.values) {
      _colorTotalCells[idx] = (_colorTotalCells[idx] ?? 0) + 1;
    }
  }

  void _updateCompletedColors() {
    if (_palette.isEmpty || _colorTotalCells.isEmpty) return;
    final Map<int, int> coloredCount = {};
    for (final idx in _cellStates.values) {
      coloredCount[idx] = (coloredCount[idx] ?? 0) + 1;
    }
    final newCompleted = <int>{};
    for (final entry in _colorTotalCells.entries) {
      if ((coloredCount[entry.key] ?? 0) >= entry.value) {
        newCompleted.add(entry.key);
      }
    }
    // Detect newly completed colors → trigger confetti
    for (final colorIdx in newCompleted) {
      if (!_completedColors.contains(colorIdx) && colorIdx < _palette.length) {
        final c = Color(_palette[colorIdx]);
        Future.microtask(() => _triggerConfetti(c));
      }
    }
    _completedColors = newCompleted;
  }

  void _checkCompletion() {
    if (_totalCells > 0 && _coloredCells >= _totalCells && !_isCompleted) {
      setState(() => _isCompleted = true);
      FirebaseService.updateRoomStatus(widget.roomId, 'completed');
      AdService.showInterstitialAd(onDismissed: () {
        if (mounted) {
          _completionController.forward();
          AdService.loadInterstitialAd();
        }
      });
    }
  }



  void _onCellTap(int x, int y) {
    if (_isReplaying) return;
    if (_isCompleted) return;

    if (_selectedColorIndex < 0) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Önce bir renk seçin!'),
          backgroundColor: AppTheme.accentOrange,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 1),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
      return;
    }

    final cellKey = '${x}_$y';
    if (_cellStates.containsKey(cellKey)) return;

    final correctColorIndex = _gridData[cellKey];
    if (correctColorIndex != null && correctColorIndex == _selectedColorIndex) {
      final wasCompleted = _completedColors.contains(_selectedColorIndex);
      setState(() {
        _cellStates[cellKey] = _selectedColorIndex;
        _coloredCells = _cellStates.length;
        _myBrushStrokes++;
        _paintHistory.add(_PaintStep(cellKey: cellKey, colorIndex: _selectedColorIndex));
        _updateCompletedColors();
      });

      FirebaseService.colorCell(
        roomId: widget.roomId,
        x: x,
        y: y,
        colorIndex: _selectedColorIndex,
        playerId: widget.playerId,
      );

      // Auto-advance to next incomplete color when current color finishes
      if (!wasCompleted && _completedColors.contains(_selectedColorIndex)) {
        _autoAdvanceColor();
      }

      _checkCompletion();
    }
  }

  // ── Günlük Bonus ────────────────────────────────────────────
  Future<void> _loadDailyBonus() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final lastDate = prefs.getString('daily_bonus_date') ?? '';
    if (lastDate == today) return; // already claimed today

    await prefs.setString('daily_bonus_date', today);
    if (!mounted) return;

    // Grant bonus charges on top of starter
    setState(() {
      _wandCharges += 3;
      _hintCharges += 2;
      _bombCharges += 1;
    });

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Row(children: [
        Text('🎁', style: TextStyle(fontSize: 20)),
        SizedBox(width: 8),
        Expanded(child: Text('Günlük bonus! ✨×3 + 💡×2 + 💣×1 kazandın!')),
      ]),
      backgroundColor: const Color(0xFF4CAF50),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  // ── Konfeti ─────────────────────────────────────────────
  void _triggerConfetti(Color color) {
    if (!mounted) return;
    setState(() {
      _confettiColor = color;
      _confettiActive = true;
    });
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _confettiActive = false);
    });
  }



  void _useWand() {
    if (_wandCharges <= 0 || _isWandAnimating) return;

    // Boyanmamış rastgele bir hücre bul
    final uncoloredCells = <String>[];
    for (final entry in _gridData.entries) {
      if (!_cellStates.containsKey(entry.key)) {
        uncoloredCells.add(entry.key);
      }
    }

    if (uncoloredCells.isEmpty) return;

    final randomCell = uncoloredCells[Random().nextInt(uncoloredCells.length)];
    final correctColor = _gridData[randomCell]!;
    final parts = randomCell.split('_');
    final x = int.parse(parts[0]);
    final y = int.parse(parts[1]);

    setState(() {
      _wandCharges--;
      _isWandAnimating = true;
      _cellStates[randomCell] = correctColor;
      _coloredCells = _cellStates.length;
      _myBrushStrokes++;
      _paintHistory.add(_PaintStep(cellKey: randomCell, colorIndex: correctColor));
      _updateCompletedColors();
    });

    FirebaseService.colorCell(
      roomId: widget.roomId,
      x: x,
      y: y,
      colorIndex: correctColor,
      playerId: widget.playerId,
    );

    _checkCompletion();

    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _isWandAnimating = false);
    });
  }

  void _autoAdvanceColor() {
    // Silently find next incomplete color after current
    for (int i = _selectedColorIndex + 1; i < _palette.length; i++) {
      if (!_completedColors.contains(i)) {
        setState(() => _selectedColorIndex = i);
        return;
      }
    }
    // Wrap to beginning
    for (int i = 0; i < _selectedColorIndex; i++) {
      if (!_completedColors.contains(i)) {
        setState(() => _selectedColorIndex = i);
        return;
      }
    }
  }

  // ── Güç Yükselticiler ──────────────────────────────────────────

  void _showPowerupDialog(PowerupType type) {
    // If charges available, use directly
    final hasCharge = switch (type) {
      PowerupType.wand => _wandCharges > 0,
      PowerupType.hint => _hintCharges > 0,
      PowerupType.bomb => _bombCharges > 0,
      PowerupType.fill => _fillCharges > 0,
    };

    if (hasCharge) {
      _usePowerup(type);
      return;
    }

    final info = switch (type) {
      PowerupType.wand => (
          emoji: '✨',
          name: 'Sihirli Değnek',
          desc: 'Rastgele bir pikseli otomatik boyar.',
          reward: '3 Sihirli Değnek',
          color: const Color(0xFFB388FF),
        ),
      PowerupType.hint => (
          emoji: '💡',
          name: 'İpucu',
          desc: 'Seçili rengin boyanmamış bir hücresini 2 saniye boyunca vurgular.',
          reward: '2 İpucu',
          color: const Color(0xFFFFD54F),
        ),
      PowerupType.bomb => (
          emoji: '💣',
          name: 'Boya Bombası',
          desc: 'Seçili rengin rastgele 10 hücresini otomatik boyar.',
          reward: '1 Bomba',
          color: const Color(0xFFFF7043),
        ),
      PowerupType.fill => (
          emoji: '🎨',
          name: 'Renk Tamamlayıcı',
          desc: 'Seçili rengin tüm kalan hücrelerini otomatik tamamlar.',
          reward: '1 Tamamlayıcı',
          color: const Color(0xFF4DD0E1),
        ),
    };

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: info.color.withValues(alpha: 0.4)),
        ),
        title: Row(
          children: [
            Text(info.emoji, style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 8),
            Text(info.name,
                style: const TextStyle(
                    color: AppTheme.textPrimary, fontWeight: FontWeight.w700)),
          ],
        ),
        content: Text(
          '${info.desc}\n\nKısa bir reklam izleyerek ${info.reward} kazanabilirsiniz!',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('İptal',
                style: TextStyle(color: AppTheme.textMuted)),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _watchAdForPowerup(type);
            },
            icon: const Icon(Icons.play_circle_filled,
                color: Colors.white, size: 20),
            label: const Text('Reklam İzle',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: info.color,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  void _watchAdForPowerup(PowerupType type) {
    AdService.showRewardedAd(
      onRewarded: () {
        setState(() {
          switch (type) {
            case PowerupType.wand:
              _wandCharges += 3;
            case PowerupType.hint:
              _hintCharges += 2;
            case PowerupType.bomb:
              _bombCharges += 1;
            case PowerupType.fill:
              _fillCharges += 1;
          }
        });
        final (emoji, msg, color) = switch (type) {
          PowerupType.wand => ('✨', '3 Sihirli Değnek kazandınız!', const Color(0xFFB388FF)),
          PowerupType.hint => ('💡', '2 İpucu kazandınız!', const Color(0xFFFFD54F)),
          PowerupType.bomb => ('💣', '1 Boya Bombası kazandınız!', const Color(0xFFFF7043)),
          PowerupType.fill => ('🎨', '1 Renk Tamamlayıcı kazandınız!', const Color(0xFF4DD0E1)),
        };
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Row(children: [
              Text(emoji, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Text(msg),
            ]),
            backgroundColor: color,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ));
        }
      },
      onDismissed: () {},
    );
  }

  void _usePowerup(PowerupType type) {
    switch (type) {
      case PowerupType.wand:
        _useWand();
      case PowerupType.hint:
        _useHint();
      case PowerupType.bomb:
        _useBomb();
      case PowerupType.fill:
        _useFill();
    }
  }

  // İpucu: seçili rengin boyanmamış bir hücresini 2 sn vurgular
  void _useHint() {
    if (_hintCharges <= 0) return;
    if (_selectedColorIndex < 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Önce bir renk seçin!'),
        backgroundColor: AppTheme.accentOrange,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ));
      return;
    }

    final uncolored = <String>[];
    for (final entry in _gridData.entries) {
      if (entry.value == _selectedColorIndex &&
          !_cellStates.containsKey(entry.key)) {
        uncolored.add(entry.key);
      }
    }

    if (uncolored.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Bu renk zaten tamamlandı!'),
        backgroundColor: AppTheme.accentGreen,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ));
      return;
    }

    // Pick a random uncolored cell for the selected color
    final target = uncolored[Random().nextInt(uncolored.length)];

    _hintTimer?.cancel();
    setState(() {
      _hintCharges--;
      _hintCellKey = target;
    });

    _hintTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _hintCellKey = null);
    });
  }

  // Boya Bombası: seçili rengin rastgele 10 hücresini boyar
  Future<void> _useBomb() async {
    if (_bombCharges <= 0) return;
    if (_selectedColorIndex < 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Önce bir renk seçin!'),
        backgroundColor: AppTheme.accentOrange,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ));
      return;
    }

    final uncolored = <String>[];
    for (final entry in _gridData.entries) {
      if (entry.value == _selectedColorIndex &&
          !_cellStates.containsKey(entry.key)) {
        uncolored.add(entry.key);
      }
    }

    if (uncolored.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Bu renk zaten tamamlandı!'),
        backgroundColor: AppTheme.accentGreen,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ));
      return;
    }

    final targetColorIndex = _selectedColorIndex;
    uncolored.shuffle();
    final targets = uncolored.take(10).toList();

    setState(() => _bombCharges--);

    for (final cellKey in targets) {
      await Future.delayed(const Duration(milliseconds: 60));
      if (!mounted) return;
      final parts = cellKey.split('_');
      final x = int.parse(parts[0]);
      final y = int.parse(parts[1]);
      setState(() {
        _cellStates[cellKey] = targetColorIndex;
        _coloredCells = _cellStates.length;
        _myBrushStrokes++;
        _paintHistory.add(_PaintStep(cellKey: cellKey, colorIndex: targetColorIndex));
        _updateCompletedColors();
      });
      FirebaseService.colorCell(
        roomId: widget.roomId,
        x: x,
        y: y,
        colorIndex: targetColorIndex,
        playerId: widget.playerId,
      );
    }
    _checkCompletion();
  }

  // Renk Tamamlayıcı: seçili rengin tüm hücrelerini boyar
  Future<void> _useFill() async {
    if (_fillCharges <= 0) return;
    if (_selectedColorIndex < 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Önce bir renk seçin!'),
        backgroundColor: AppTheme.accentOrange,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ));
      return;
    }

    final uncolored = <String>[];
    for (final entry in _gridData.entries) {
      if (entry.value == _selectedColorIndex &&
          !_cellStates.containsKey(entry.key)) {
        uncolored.add(entry.key);
      }
    }

    if (uncolored.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Bu renk zaten tamamlandı!'),
        backgroundColor: AppTheme.accentGreen,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ));
      return;
    }

    final targetColorIndex = _selectedColorIndex;
    setState(() => _fillCharges--);

    // Wave fill animation — paint in small batches
    const batchSize = 15;
    for (int i = 0; i < uncolored.length; i += batchSize) {
      await Future.delayed(const Duration(milliseconds: 40));
      if (!mounted) return;
      final batch = uncolored.skip(i).take(batchSize);
      setState(() {
        for (final cellKey in batch) {
          _cellStates[cellKey] = targetColorIndex;
          _paintHistory.add(_PaintStep(cellKey: cellKey, colorIndex: targetColorIndex));
          _myBrushStrokes++;
        }
        _coloredCells = _cellStates.length;
        _updateCompletedColors();
      });
      for (final cellKey in batch) {
        final parts = cellKey.split('_');
        FirebaseService.colorCell(
          roomId: widget.roomId,
          x: int.parse(parts[0]),
          y: int.parse(parts[1]),
          colorIndex: targetColorIndex,
          playerId: widget.playerId,
        );
      }
    }
    _checkCompletion();
    if (!widget.isSolo) _autoAdvanceColor();
  }


  void _startReplay() {
    if (_paintHistory.isEmpty) return;
    setState(() {
      _isReplaying = true;
      _replayCellStates = {};
      _replayStep = 0;
    });
    _scheduleNextReplayStep();
  }

  void _scheduleNextReplayStep() {
    final delay = _paintHistory.length > 500
        ? 8
        : _paintHistory.length > 200
            ? 15
            : 25;
    _replayTimer = Timer(Duration(milliseconds: delay), () {
      if (!mounted) return;
      if (_replayStep >= _paintHistory.length) {
        // Replay done — stop timer but keep the final painted view visible
        _replayTimer?.cancel();
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted) setState(() => _isReplaying = false);
        });
        return;
      }
      setState(() {
        final step = _paintHistory[_replayStep];
        _replayCellStates[step.cellKey] = step.colorIndex;
        _replayStep++;
      });
      _scheduleNextReplayStep();
    });
  }

  void _stopReplay() {
    _replayTimer?.cancel();
    // Keep _isReplaying = true, just stop the timer, so user sees the result
    setState(() {
      _isReplaying = false;
    });
  }

  // ── Save to Gallery ────────────────────────────────────────────
  Future<void> _saveToGallery() async {
    try {
      // Render grid to image
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      const double pixelSize = 8.0;
      final w = _gridWidth * pixelSize;
      final h = _gridHeight * pixelSize;

      // Background
      canvas.drawRect(
        Rect.fromLTWH(0, 0, w, h),
        Paint()..color = const Color(0xFF1C2128),
      );

      final paint = Paint()..isAntiAlias = false;
      for (int y = 0; y < _gridHeight; y++) {
        for (int x = 0; x < _gridWidth; x++) {
          final cellKey = '${x}_$y';
          final rect = Rect.fromLTWH(x * pixelSize, y * pixelSize, pixelSize, pixelSize);
          if (_cellStates.containsKey(cellKey)) {
            final ci = _cellStates[cellKey]!;
            paint.color = ci < _palette.length ? Color(_palette[ci]) : Colors.grey;
            canvas.drawRect(rect, paint);
          }
        }
      }

      final picture = recorder.endRecording();
      final image = await picture.toImage(w.toInt(), h.toInt());
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);

      if (bytes != null) {
        await Gal.putImageBytes(bytes.buffer.asUint8List(), name: 'boyama_${DateTime.now().millisecondsSinceEpoch}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                  SizedBox(width: 8),
                  Text('Galeriye kaydedildi!'),
                ],
              ),
              backgroundColor: AppTheme.accentGreen,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              margin: const EdgeInsets.all(16),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Kayıt hatası: $e'),
            backgroundColor: const Color(0xFFF85149),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    }
  }

  // ── Exit Dialog ────────────────────────────────────────────────
  void _showExitDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppTheme.borderDark),
        ),
        title: const Text('Oyundan Çık?',
            style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700)),
        content: const Text(
          'Oyundan çıkarsanız ilerleme kaybolabilir.',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('İptal', style: TextStyle(color: AppTheme.textMuted)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (!widget.isSolo) _agoraService.leaveChannel();
              if (widget.isHost) FirebaseService.deleteRoom(widget.roomId);
              Navigator.popUntil(context, (route) => route.isFirst);
            },
            child: const Text('Çık',
                style: TextStyle(color: Color(0xFFF85149), fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Future<void> _exportTimeLapse() async {
    if (_paintHistory.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Henüz hiçbir hücre boyanmadı'),
          backgroundColor: AppTheme.accentOrange,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        backgroundColor: AppTheme.surfaceDark,
        content: Row(
          children: [
            CircularProgressIndicator(color: AppTheme.accentPurple),
            SizedBox(width: 16),
            Expanded(
              child: Text(
                'Hızlı Çekim (GIF) hazırlanıyor...\nBu işlem biraz sürebilir.',
                style: TextStyle(color: AppTheme.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );

    try {
      final int scale = 4;
      final w = _gridWidth * scale;
      final h = _gridHeight * scale;

      final animation = img.Image(width: w, height: h);
      
      final int totalFrames = min(20, _paintHistory.length);
      final double stepSize = _paintHistory.length / totalFrames;
      
      Map<String, int> currentStates = {};
      
      for (int i = 0; i <= totalFrames; i++) {
        int historyIndex = (i * stepSize).round();
        if (historyIndex > _paintHistory.length) historyIndex = _paintHistory.length;
        if (historyIndex == 0 && i > 0) continue;
        
        for (int j = currentStates.length; j < historyIndex; j++) {
          final step = _paintHistory[j];
          currentStates[step.cellKey] = step.colorIndex;
        }
        
        final frame = img.Image(width: w, height: h);
        
        for (int y = 0; y < _gridHeight; y++) {
          for (int x = 0; x < _gridWidth; x++) {
            final key = '${x}_$y';
            if (currentStates.containsKey(key)) {
              final ci = currentStates[key]!;
              if (ci < _palette.length) {
                final colorVal = _palette[ci];
                final r = (colorVal >> 16) & 0xFF;
                final g = (colorVal >> 8) & 0xFF;
                final b = colorVal & 0xFF;
                img.fillRect(frame, x1: x * scale, y1: y * scale, x2: x * scale + scale - 1, y2: y * scale + scale - 1, color: img.ColorRgb8(r, g, b));
              }
            } else {
              img.fillRect(frame, x1: x * scale, y1: y * scale, x2: x * scale + scale - 1, y2: y * scale + scale - 1, color: img.ColorRgb8(245, 242, 236)); 
            }
          }
        }
        
        if (i == 0) {
           animation.frames[0] = frame;
           animation.frames[0].frameDuration = 200;
        } else {
           frame.frameDuration = 200;
           animation.addFrame(frame);
        }
      }
      
      final gifBytes = await compute(_encodeGifIsolate, animation);
      
      if (mounted) Navigator.pop(context); // close dialog
      
      if (gifBytes != null) {
        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/timelapse.gif');
        await file.writeAsBytes(gifBytes);
        await Share.shareXFiles([XFile(file.path)], text: 'Boyamamın hızlı çekimi!');
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // close dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('GIF oluşturulurken hata: $e'),
            backgroundColor: const Color(0xFFF85149),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _triggerReaction(String emoji) {
    final id = DateTime.now().millisecondsSinceEpoch.toString() + Random().nextInt(1000).toString();
    final startX = 0.1 + Random().nextDouble() * 0.8;
    setState(() {
      _floatingEmojis.add(_ActiveEmoji(id, emoji, startX));
    });
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _floatingEmojis.removeWhere((e) => e.id == id);
        });
      }
    });
  }

  Widget _buildFloatingEmoji(_ActiveEmoji activeEmoji) {
    return Positioned(
      left: MediaQuery.of(context).size.width * activeEmoji.startX,
      bottom: 120,
      child: TweenAnimationBuilder<double>(
        key: ValueKey(activeEmoji.id),
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(seconds: 2),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) {
          return Transform.translate(
            offset: Offset(0, -value * 300),
            child: Opacity(
              opacity: 1.0 - value,
              child: Text(
                activeEmoji.emoji,
                style: const TextStyle(fontSize: 48),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0D1117), Color(0xFF161B22)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: AppTheme.accentPurple),
                SizedBox(height: 16),
                Text('Oyun yükleniyor...',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 16)),
              ],
            ),
          ),
        ),
      );
    }

    final double progress = _totalCells > 0 ? _coloredCells / _totalCells : 0;
    final displayCellStates = _isReplaying ? _replayCellStates : _cellStates;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0D1117), Color(0xFF161B22)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  // Top bar
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: _showExitDialog,
                          icon: const Icon(Icons.close_rounded),
                          color: AppTheme.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    widget.isSolo ? 'Solo Boyama' : 'Co-op Boyama',
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                  if (_isReplaying) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppTheme.accentPurple.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.play_circle_filled_rounded,
                                              size: 11, color: AppTheme.accentPurple),
                                          const SizedBox(width: 3),
                                          Text(
                                            'TEKRAR $_replayStep/${_paintHistory.length}',
                                            style: TextStyle(
                                              color: AppTheme.accentPurple,
                                              fontSize: 9,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 4),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: progress,
                                  minHeight: 6,
                                  backgroundColor: AppTheme.cardDark,
                                  valueColor: AlwaysStoppedAnimation(
                                    progress >= 1.0 ? AppTheme.accentGreen : AppTheme.accentPurple,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Counter
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppTheme.cardDark,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.borderDark),
                          ),
                          child: Text(
                            '$_coloredCells/$_totalCells',
                            style: const TextStyle(
                              color: AppTheme.accentBlue,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        if (!widget.isSolo) ...[
                          const SizedBox(width: 4),
                          Stack(
                            alignment: Alignment.topRight,
                            children: [
                              IconButton(
                                icon: Icon(
                                  _isMicMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                                  color: _isMicMuted ? const Color(0xFFF85149) : AppTheme.accentGreen,
                                ),
                                onPressed: () async {
                                  await _agoraService.toggleMute();
                                  setState(() {
                                    _isMicMuted = _agoraService.isMuted;
                                  });
                                },
                              ),
                              if (_remoteUserCount > 0)
                                Container(
                                  margin: const EdgeInsets.only(top: 8, right: 8),
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: AppTheme.accentGreen,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                            ],
                          ),
                        ],
                        const SizedBox(width: 4),
                        // Action menu
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert_rounded, color: AppTheme.textSecondary),
                          color: AppTheme.surfaceDark,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: const BorderSide(color: AppTheme.borderDark),
                          ),
                          onSelected: (val) async {
                            if (val == 'replay') _startReplay();
                            if (val == 'save') _saveToGallery();
                            if (val == 'stop_replay') _stopReplay();
                            if (val == 'timelapse') _exportTimeLapse();
                            if (val == 'photo') {
                              // Render painted grid to image
                              if (_cellStates.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: const Text('Henüz hiçbir hücre boyanmadı'),
                                    backgroundColor: AppTheme.accentOrange,
                                    behavior: SnackBarBehavior.floating,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    margin: const EdgeInsets.all(16),
                                  ),
                                );
                                return;
                              }
                              final recorder = ui.PictureRecorder();
                              final canvas = Canvas(recorder);
                              const double px = 8.0;
                              final w = _gridWidth * px;
                              final h = _gridHeight * px;
                              // White background for uncolored cells
                              canvas.drawRect(Rect.fromLTWH(0, 0, w, h),
                                  Paint()..color = const Color(0xFFF5F2EC));
                              final paint = Paint()..isAntiAlias = false;
                              for (int y = 0; y < _gridHeight; y++) {
                                for (int x = 0; x < _gridWidth; x++) {
                                  final key = '${x}_$y';
                                  if (_cellStates.containsKey(key)) {
                                    final ci = _cellStates[key]!;
                                    paint.color = ci < _palette.length
                                        ? Color(_palette[ci])
                                        : Colors.grey;
                                    canvas.drawRect(
                                        Rect.fromLTWH(x * px, y * px, px, px), paint);
                                  }
                                }
                              }
                              final picture = recorder.endRecording();
                              final img = await picture.toImage(w.toInt(), h.toInt());
                              final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
                              if (!mounted) return;
                              if (byteData == null) return;
                              final bytes = byteData.buffer.asUint8List();
                              showDialog(
                                context: context,
                                builder: (_) => Dialog(
                                  backgroundColor: Colors.black87,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const SizedBox(height: 16),
                                      const Text('Boyanmış Hali',
                                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                                      const SizedBox(height: 12),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: Image.memory(bytes, fit: BoxFit.contain),
                                      ),
                                      const SizedBox(height: 12),
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: const Text('Kapat',
                                            style: TextStyle(color: AppTheme.accentPurple, fontSize: 16, fontWeight: FontWeight.w600)),
                                      ),
                                      const SizedBox(height: 8),
                                    ],
                                  ),
                                ),
                              );
                            }
                          },
                          itemBuilder: (_) => [
                            if (_isReplaying)
                              const PopupMenuItem(
                                value: 'stop_replay',
                                child: Row(children: [
                                  Icon(Icons.stop_rounded, color: AppTheme.accentOrange, size: 20),
                                  SizedBox(width: 10),
                                  Text('Durdur', style: TextStyle(color: AppTheme.textPrimary)),
                                ]),
                              )
                            else ...[
                              const PopupMenuItem(
                                value: 'photo',
                                child: Row(children: [
                                  Icon(Icons.image_rounded, color: AppTheme.accentBlue, size: 20),
                                  SizedBox(width: 10),
                                  Text('Orijinal Fotoğrafı Gör', style: TextStyle(color: AppTheme.textPrimary)),
                                ]),
                              ),
                              const PopupMenuItem(
                                value: 'replay',
                                child: Row(children: [
                                  Icon(Icons.replay_rounded, color: AppTheme.accentPurple, size: 20),
                                  SizedBox(width: 10),
                                  Text('Boyamayı Tekrar İzle', style: TextStyle(color: AppTheme.textPrimary)),
                                ]),
                              ),
                              const PopupMenuItem(
                                value: 'save',
                                child: Row(children: [
                                  Icon(Icons.download_rounded, color: AppTheme.accentGreen, size: 20),
                                  SizedBox(width: 10),
                                  Text('Galeriye Kaydet', style: TextStyle(color: AppTheme.textPrimary)),
                                ]),
                              ),
                              const PopupMenuItem(
                                value: 'timelapse',
                                child: Row(children: [
                                  Icon(Icons.movie_creation_rounded, color: AppTheme.accentPink, size: 20),
                                  SizedBox(width: 10),
                                  Text('Hızlı Çekim Paylaş', style: TextStyle(color: AppTheme.textPrimary)),
                                ]),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Grid canvas
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDDD9D0),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.borderDark),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: InteractiveViewer(
                          transformationController: _transformController,
                          minScale: 0.4,
                          maxScale: 12.0,
                          boundaryMargin: const EdgeInsets.all(200),
                          panEnabled: false,
                          scaleEnabled: true,
                          child: Center(
                            child: RepaintBoundary(
                              key: _gridRepaintKey,
                              child: PixelGrid(
                                width: _gridWidth,
                                height: _gridHeight,
                                gridData: _gridData,
                                cellStates: displayCellStates,
                                palette: _palette,
                                selectedColorIndex: _isReplaying ? -1 : _selectedColorIndex,
                                hintCellKey: _hintCellKey,
                                onCellTap: _onCellTap,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Palette
                  if (!_isReplaying)
                    ColorPaletteBar(
                      palette: _palette,
                      selectedIndex: _selectedColorIndex,
                      completedColors: _completedColors,
                      onColorSelected: (index) {
                        setState(() => _selectedColorIndex = index);
                      },
                    ),

                  // Powerups Bar
                  if (!_isReplaying && !_isCompleted)
                    PowerupsBar(
                      wandCharges: _wandCharges,
                      hintCharges: _hintCharges,
                      bombCharges: _bombCharges,
                      fillCharges: _fillCharges,
                      onTap: _showPowerupDialog,
                    ),

                  // Emoji Bar
                  if (!widget.isSolo && !_isReplaying && !_isCompleted)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: ['❤️', '😂', '👍', '🔥', '👏'].map((emoji) {
                          return GestureDetector(
                            onTap: () {
                              FirebaseService.sendEmoji(widget.roomId, emoji, widget.playerId);
                              _triggerReaction(emoji); // Trigger locally immediately for better UX
                            },
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppTheme.cardDark,
                                shape: BoxShape.circle,
                                border: Border.all(color: AppTheme.borderDark),
                              ),
                              child: Text(emoji, style: const TextStyle(fontSize: 24)),
                            ),
                          );
                        }).toList(),
                      ),
                    ),

                  if (_isReplaying)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: LinearProgressIndicator(
                              value: _paintHistory.isNotEmpty ? _replayStep / _paintHistory.length : 0,
                              minHeight: 8,
                              borderRadius: BorderRadius.circular(4),
                              backgroundColor: AppTheme.cardDark,
                              valueColor: const AlwaysStoppedAnimation(AppTheme.accentPurple),
                            ),
                          ),
                          const SizedBox(width: 12),
                          GestureDetector(
                            onTap: _stopReplay,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: AppTheme.accentOrange.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: AppTheme.accentOrange.withValues(alpha: 0.5)),
                              ),
                              child: const Text('Durdur',
                                  style: TextStyle(
                                      color: AppTheme.accentOrange, fontWeight: FontWeight.w700)),
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 8),
                ],
              ),

              // Completion overlay
              if (_isCompleted && !_isReplaying)
                _CompletionOverlay(
                  animation: _completionAnimation,
                  paintCount: _coloredCells, // total from both players
                  myPaintCount: _myBrushStrokes,
                  isMultiplayer: !widget.isSolo,
                  onGoHome: () => Navigator.popUntil(context, (route) => route.isFirst),
                  onReplay: _paintHistory.isNotEmpty ? _startReplay : null,
                  onSave: _saveToGallery,
                ),

              // Floating Emojis
              ..._floatingEmojis.map((e) => _buildFloatingEmoji(e)),

              // Konfeti Overlay
              Positioned.fill(
                child: ConfettiBurst(
                  primaryColor: _confettiColor,
                  active: _confettiActive,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PaintStep {
  final String cellKey;
  final int colorIndex;
  const _PaintStep({required this.cellKey, required this.colorIndex});
}

Uint8List? _encodeGifIsolate(img.Image animation) {
  return img.encodeGif(animation);
}

class _ActiveEmoji {
  final String id;
  final String emoji;
  final double startX;
  _ActiveEmoji(this.id, this.emoji, this.startX);
}

// ── Completion Overlay ─────────────────────────────────────────────────────────
class _CompletionOverlay extends AnimatedWidget {
  final VoidCallback onGoHome;
  final VoidCallback? onReplay;
  final VoidCallback onSave;
  final int paintCount;
  final int myPaintCount;
  final bool isMultiplayer;

  const _CompletionOverlay({
    required Animation<double> animation,
    required this.onGoHome,
    required this.onSave,
    required this.paintCount,
    required this.myPaintCount,
    required this.isMultiplayer,
    this.onReplay,
  }) : super(listenable: animation);

  @override
  Widget build(BuildContext context) {
    final animation = listenable as Animation<double>;
    return Opacity(
      opacity: animation.value.clamp(0.0, 1.0),
      child: Container(
        color: Colors.black.withValues(alpha: 0.65),
        child: Center(
          child: Transform.scale(
            scale: animation.value.clamp(0.0, 1.0),
            child: Container(
              margin: const EdgeInsets.all(28),
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: AppTheme.surfaceDark,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: AppTheme.accentGreen, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.accentGreen.withValues(alpha: 0.3),
                    blurRadius: 40,
                    spreadRadius: 8,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Trophy icon
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      gradient: AppTheme.greenGradient,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.accentGreen.withValues(alpha: 0.5),
                          blurRadius: 24,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.emoji_events_rounded, color: Colors.white, size: 44),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Tebrikler! 🎉',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textPrimary,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Boyamayı tamamladınız!',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  if (paintCount > 0) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppTheme.cardDark,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.borderDark),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.brush_rounded, color: AppTheme.accentPurple, size: 16),
                              const SizedBox(width: 6),
                              Text(
                                isMultiplayer
                                    ? 'Toplam $paintCount fırça darbesi'
                                    : '$paintCount fırça darbesi',
                                style: const TextStyle(
                                  color: AppTheme.accentPurple,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          if (isMultiplayer) ...[
                            const SizedBox(height: 6),
                            Text(
                              'Senin katkın: $myPaintCount darbe  •  Diğer oyuncu: ${paintCount - myPaintCount} darbe',
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  // Save button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: AppTheme.greenGradient,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.accentGreen.withValues(alpha: 0.35),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ElevatedButton.icon(
                        onPressed: onSave,
                        icon: const Icon(Icons.download_rounded, color: Colors.white, size: 18),
                        label: const Text('Galeriye Kaydet',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                  ),
                  // Replay button
                  if (onReplay != null) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: onReplay,
                        icon: const Icon(Icons.replay_rounded, color: AppTheme.accentPurple, size: 18),
                        label: const Text('Boyamayı İzle',
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.accentPurple)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppTheme.accentPurple, width: 1.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  // Home button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: AppTheme.primaryGradient,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: ElevatedButton(
                        onPressed: onGoHome,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: const Text('Ana Menüye Dön',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
