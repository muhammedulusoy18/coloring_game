import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import '../services/firebase_service.dart';
import '../services/ad_service.dart';
import '../utils/app_theme.dart';
import '../widgets/color_palette_bar.dart';
import '../widgets/pixel_grid.dart';

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

  // Completed colors tracking
  Set<int> _completedColors = {};
  Map<int, int> _colorTotalCells = {}; // colorIndex -> total cells

  // For save to gallery
  final GlobalKey _gridRepaintKey = GlobalKey();

  // For gesture coordinate conversion
  final TransformationController _transformController = TransformationController();

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
  }

  @override
  void dispose() {
    _roomSub?.cancel();
    _cellAddSub?.cancel();
    _cellChangeSub?.cancel();
    _completionController.dispose();
    _replayTimer?.cancel();
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
    // Wrong color: silent (no snackbar spam during drag)
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

  // ── Replay ─────────────────────────────────────────────────────
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
        // Replay done
        Future.delayed(const Duration(milliseconds: 800), () {
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
    setState(() => _isReplaying = false);
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
                        const SizedBox(width: 4),
                        // Action menu
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert_rounded, color: AppTheme.textSecondary),
                          color: AppTheme.surfaceDark,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: const BorderSide(color: AppTheme.borderDark),
                          ),
                          onSelected: (val) {
                            if (val == 'replay') _startReplay();
                            if (val == 'save') _saveToGallery();
                            if (val == 'stop_replay') _stopReplay();
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
                              if (_paintHistory.isNotEmpty)
                                const PopupMenuItem(
                                  value: 'replay',
                                  child: Row(children: [
                                    Icon(Icons.replay_rounded, color: AppTheme.accentPurple, size: 20),
                                    SizedBox(width: 10),
                                    Text('Boyamayı Tekrar İzle',
                                        style: TextStyle(color: AppTheme.textPrimary)),
                                  ]),
                                ),
                              const PopupMenuItem(
                                value: 'save',
                                child: Row(children: [
                                  Icon(Icons.download_rounded, color: AppTheme.accentGreen, size: 20),
                                  SizedBox(width: 10),
                                  Text('Galeriye Kaydet',
                                      style: TextStyle(color: AppTheme.textPrimary)),
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
                  paintCount: _paintHistory.length,
                  onGoHome: () => Navigator.popUntil(context, (route) => route.isFirst),
                  onReplay: _paintHistory.isNotEmpty ? _startReplay : null,
                  onSave: _saveToGallery,
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

// ── Completion Overlay ─────────────────────────────────────────────────────────
class _CompletionOverlay extends AnimatedWidget {
  final VoidCallback onGoHome;
  final VoidCallback? onReplay;
  final VoidCallback onSave;
  final int paintCount;

  const _CompletionOverlay({
    required Animation<double> animation,
    required this.onGoHome,
    required this.onSave,
    required this.paintCount,
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
                    const SizedBox(height: 8),
                    Text(
                      '$paintCount fırça darbesi',
                      style: const TextStyle(
                        color: AppTheme.accentPurple,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
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
