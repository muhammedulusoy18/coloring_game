import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../models/game_room.dart';
import '../services/firebase_service.dart';
import '../services/image_processor_service.dart';
import '../utils/app_theme.dart';
import 'game_screen.dart';

class LobbyScreen extends StatefulWidget {
  final GameRoom room;
  final String playerId;
  final bool isHost;
  final bool isSolo;

  const LobbyScreen({
    super.key,
    required this.room,
    required this.playerId,
    required this.isHost,
    this.isSolo = false,
  });

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> with TickerProviderStateMixin {
  late GameRoom _room;
  StreamSubscription? _roomSubscription;
  bool _isProcessingImage = false;
  double _processingProgress = 0.0;
  String _processingStatus = '';
  late AnimationController _dotController;
  GameDifficulty _selectedDifficulty = GameDifficulty.medium;

  @override
  void initState() {
    super.initState();
    _room = widget.room;
    _dotController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();

    _roomSubscription = FirebaseService.listenToRoom(
      _room.roomId,
      (updatedRoom) {
        setState(() => _room = updatedRoom);

        // If game starts and we're the guest, navigate to game
        if (updatedRoom.status == 'playing' && !widget.isHost) {
          _navigateToGame();
        }
      },
    );
  }

  @override
  void dispose() {
    _roomSubscription?.cancel();
    _dotController.dispose();
    super.dispose();
  }

  Future<void> _pickAndProcessImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );

    if (pickedFile == null) return;

    setState(() {
      _isProcessingImage = true;
      _processingProgress = 0.1;
      _processingStatus = 'Görsel okunuyor...';
    });

    try {
      final bytes = await File(pickedFile.path).readAsBytes();
      await _processImageBytes(bytes);
    } catch (e) {
      _handleProcessingError(e);
    }
  }

  Future<void> _pickTemplate(String filename) async {
    setState(() {
      _isProcessingImage = true;
      _processingProgress = 0.1;
      _processingStatus = 'Şablon yükleniyor...';
      // _selectedDifficulty is no longer changed here!
    });

  Future<void> _processImageBytes(Uint8List bytes) async {
    setState(() {
      _processingProgress = 0.3;
      _processingStatus = 'Piksel grid\'e dönüştürülüyor...';
    });

    final result = await ImageProcessorService.processImage(
      bytes,
      difficulty: _selectedDifficulty,
    );

    setState(() {
      _processingProgress = 0.6;
      _processingStatus = 'Renk paleti oluşturuluyor...';
    });

    await Future.delayed(const Duration(milliseconds: 300));

    setState(() {
      _processingProgress = 0.8;
      _processingStatus = 'Firebase\'e yükleniyor...';
    });

    await FirebaseService.uploadGridData(
      roomId: _room.roomId,
      width: result.width,
      height: result.height,
      palette: result.palette,
      gridData: result.gridData,
      imageBytes: bytes,
    );

    setState(() {
      _processingProgress = 1.0;
      _processingStatus = 'Hazır! Oyun başlıyor...';
    });

    await Future.delayed(const Duration(milliseconds: 500));

    if (mounted) {
      _navigateToGame();
    }
  }

  void _handleProcessingError(dynamic e) {
    setState(() {
      _isProcessingImage = false;
      _processingProgress = 0;
      _processingStatus = '';
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Görsel işleme hatası: $e'),
          backgroundColor: const Color(0xFFF85149),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  void _navigateToGame() {
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => GameScreen(
          roomId: _room.roomId,
          playerId: widget.playerId,
          isHost: widget.isHost,
          isSolo: widget.isSolo,
        ),
        transitionsBuilder: (_, anim, __, child) {
          return FadeTransition(
            opacity: CurvedAnimation(parent: anim, curve: Curves.easeIn),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 600),
      ),
    );
  }

  void _copyPin() {
    Clipboard.setData(ClipboardData(text: _room.pin));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('PIN kopyalandı!'),
        backgroundColor: AppTheme.accentGreen,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasGuest = _room.guestId != null && _room.guestId!.isNotEmpty;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF0D1117),
              Color(0xFF161B22),
              Color(0xFF1A1040),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                // Header
                Row(
                  children: [
                    IconButton(
                      onPressed: () {
                        if (widget.isHost) {
                          FirebaseService.deleteRoom(_room.roomId);
                        }
                        Navigator.pop(context);
                      },
                      icon: const Icon(Icons.arrow_back_ios_rounded),
                      color: AppTheme.textSecondary,
                    ),
                    Expanded(
                      child: Text(
                        widget.isHost ? 'Odan Hazır' : 'Lobide Bekliyorsun',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
                const SizedBox(height: 32),

                // PIN Display Card
                if (widget.isHost) ...[
                  GestureDetector(
                    onTap: _copyPin,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceDark,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: AppTheme.borderDark),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.accentPurple.withValues(alpha: 0.1),
                            blurRadius: 30,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.vpn_key_rounded,
                                color: AppTheme.accentPurple,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'GAME PIN',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: AppTheme.accentPurple,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 3,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          ShaderMask(
                            shaderCallback: (bounds) => AppTheme.primaryGradient.createShader(bounds),
                            child: Text(
                              _room.pin,
                              style: const TextStyle(
                                fontSize: 48,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: 16,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.copy_rounded,
                                size: 14,
                                color: AppTheme.textMuted,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Kopyalamak için dokun',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: AppTheme.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                // Players Status
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceDark,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppTheme.borderDark),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Oyuncular',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Host
                      _buildPlayerRow(
                        icon: Icons.star_rounded,
                        iconColor: AppTheme.accentOrange,
                        label: _room.hostName ?? 'Oda Sahibi',
                        isConnected: true,
                        isYou: widget.isHost,
                      ),
                      const SizedBox(height: 12),
                      // Guest
                      _buildPlayerRow(
                        icon: Icons.person_rounded,
                        iconColor: AppTheme.accentBlue,
                        label: hasGuest ? (_room.guestName ?? 'Oyuncu 2') : 'Bekleniyor...',
                        isConnected: hasGuest,
                        isYou: !widget.isHost && hasGuest,
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                // Processing indicator or action button
                if (_isProcessingImage) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceDark,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppTheme.borderDark),
                    ),
                    child: Column(
                      children: [
                        Text(
                          _processingStatus,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: AppTheme.accentPurple,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: _processingProgress,
                            minHeight: 8,
                            backgroundColor: AppTheme.cardDark,
                            valueColor: const AlwaysStoppedAnimation(AppTheme.accentPurple),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${(_processingProgress * 100).toInt()}%',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else if (widget.isSolo || (widget.isHost && hasGuest)) ...[
                  // Difficulty selector
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceDark,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.borderDark),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Zorluk Seviyesi',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: GameDifficulty.values.map((d) {
                            final isSelected = d == _selectedDifficulty;
                            return Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() => _selectedDifficulty = d),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  margin: const EdgeInsets.only(right: 6),
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? AppTheme.accentPurple.withValues(alpha: 0.2)
                                        : AppTheme.cardDark,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: isSelected ? AppTheme.accentPurple : AppTheme.borderDark,
                                      width: isSelected ? 1.5 : 1,
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      Text(
                                        d.label,
                                        style: TextStyle(
                                          color: isSelected ? AppTheme.accentPurple : AppTheme.textMuted,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        d.description,
                                        style: TextStyle(
                                          color: isSelected
                                              ? AppTheme.accentPurple.withValues(alpha: 0.7)
                                              : AppTheme.textMuted.withValues(alpha: 0.6),
                                          fontSize: 8,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Action Buttons
                  Row(
                    children: [
                      Expanded(
                        child: _buildActionButton(
                          icon: Icons.grid_view_rounded,
                          label: 'Şablon Seç',
                          onPressed: _showTemplatePicker,
                          gradient: AppTheme.blueGradient,
                          shadowColor: AppTheme.accentBlue,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildActionButton(
                          icon: Icons.photo_library_rounded,
                          label: 'Galeriden',
                          onPressed: _pickAndProcessImage,
                          gradient: AppTheme.pinkGradient,
                          shadowColor: AppTheme.accentPink,
                        ),
                      ),
                    ],
                  ),
                ] else if (widget.isHost && !hasGuest) ...[
                  _WaitingDotsWidget(
                    animation: _dotController,
                    textTheme: Theme.of(context).textTheme,
                  ),
                ] else if (!widget.isHost) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppTheme.cardDark,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.borderDark),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: AppTheme.accentPurple,
                            strokeWidth: 2,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Oda sahibi fotoğraf seçiyor...',
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlayerRow({
    required IconData icon,
    required Color iconColor,
    required String label,
    required bool isConnected,
    required bool isYou,
  }) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: iconColor, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: isConnected ? AppTheme.textPrimary : AppTheme.textMuted,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  if (isYou) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.accentPurple.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'Sen',
                        style: TextStyle(
                          color: AppTheme.accentPurple,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isConnected ? AppTheme.accentGreen : AppTheme.textMuted.withValues(alpha: 0.3),
            boxShadow: isConnected
                ? [BoxShadow(color: AppTheme.accentGreen.withValues(alpha: 0.5), blurRadius: 8)]
                : null,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required Gradient gradient,
    required Color shadowColor,
  }) {
    return SizedBox(
      height: 60,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: shadowColor.withValues(alpha: 0.4),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ElevatedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, color: Colors.white, size: 20),
          label: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
      ),
    );
  }

  void _showTemplatePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceDark,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (bottomSheetContext) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Bir Şablon Seç',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 20),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 3,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.9,
                children: [
                  _buildTemplateCard('Köpek', 'dog', AppTheme.accentOrange, bottomSheetContext),
                  _buildTemplateCard('Kedi', 'cat', AppTheme.accentPurple, bottomSheetContext),
                  _buildTemplateCard('Ev', 'house', AppTheme.accentGreen, bottomSheetContext),
                  _buildTemplateCard('Çiçek', 'flower', AppTheme.accentPink, bottomSheetContext),
                  _buildTemplateCard('Araba', 'car', AppTheme.accentBlue, bottomSheetContext),
                  _buildTemplateCard('Roket', 'rocket', AppTheme.accentOrange, bottomSheetContext),
                  _buildTemplateCard('Kiraz', 'easy', AppTheme.accentGreen, bottomSheetContext), 
                  _buildTemplateCard('Gitar', 'medium', AppTheme.accentOrange, bottomSheetContext), 
                  _buildTemplateCard('Manzara', 'hard', AppTheme.accentPink, bottomSheetContext), 
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTemplateCard(String label, String templateName, Color color, [BuildContext? bottomSheetContext]) {
    return GestureDetector(
      onTap: () {
        if (bottomSheetContext != null) {
          Navigator.pop(bottomSheetContext);
        }
        _pickTemplate(templateName);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Image.asset(
              'assets/templates/$templateName.png',
              width: 40,
              height: 40,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Icon(Icons.image, color: color, size: 30),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WaitingDotsWidget extends AnimatedWidget {
  final TextTheme textTheme;

  const _WaitingDotsWidget({
    required Animation<double> animation,
    required this.textTheme,
  }) : super(listenable: animation);

  @override
  Widget build(BuildContext context) {
    final animation = listenable as Animation<double>;
    int dots = (animation.value * 3).floor() + 1;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderDark),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              color: AppTheme.accentBlue,
              strokeWidth: 2,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Oyuncu bekleniyor${'.' * dots}',
            style: textTheme.bodyLarge?.copyWith(
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
