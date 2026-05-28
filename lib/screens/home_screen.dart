import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/app_theme.dart';
import '../services/firebase_service.dart';
import '../services/ad_service.dart';
import 'lobby_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late AnimationController _pulseController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _pulseAnimation;
  String _playerId = '';
  final TextEditingController _pinController = TextEditingController();
  bool _isJoining = false;
  bool _isBannerAdLoaded = false;
  String? _lastRoomPin; // Son katılınan oda PIN'i
  static const String _prefKeyLastPin = 'last_room_pin';
  static const String _prefKeyPlayerId = 'player_id';

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);

    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _fadeController.forward();
    _initSessionData();
    // Banner reklamı yükle
    AdService.loadBannerAd(onLoaded: () {
      if (mounted) setState(() => _isBannerAdLoaded = true);
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _pulseController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _initSessionData() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Load or generate Player ID
    String? savedId = prefs.getString(_prefKeyPlayerId);
    if (savedId == null || savedId.isEmpty) {
      savedId = FirebaseService.generatePlayerId();
      await prefs.setString(_prefKeyPlayerId, savedId);
    }
    if (mounted) setState(() => _playerId = savedId!);

    // Load username
    String? username = prefs.getString('username');
    if (username == null || username.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showNameDialog();
      });
    }

    // Load last room PIN
    final pin = prefs.getString(_prefKeyLastPin);
    if (mounted && pin != null && pin.isNotEmpty) {
      setState(() => _lastRoomPin = pin);
    }
  }

  Future<void> _saveLastRoomPin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyLastPin, pin);
  }

  Future<void> _clearLastRoomPin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKeyLastPin);
    if (mounted) setState(() => _lastRoomPin = null);
  }

  void _showNameDialog() {
    final TextEditingController nameController = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: AppTheme.surfaceDark,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text('Hoş Geldin!', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Oyunda görünmesi için bir isim belirle:', style: TextStyle(color: AppTheme.textMuted)),
              const SizedBox(height: 16),
              TextField(
                controller: nameController,
                autofocus: true,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Örn: PikselCengo',
                  hintStyle: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.5)),
                  filled: true,
                  fillColor: AppTheme.cardDark,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isNotEmpty) {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('username', name);
                  if (mounted) Navigator.pop(context);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentGreen,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Başla', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createRoom() async {
    if (_playerId.isEmpty) return; // session tam yüklenmediyse bekle
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: AppTheme.accentPurple),
      ),
    );

    try {
      final room = await FirebaseService.createRoom(_playerId);
      
      // Host da oluşturduğu odaya daha sonra geri dönebilmeli
      await _saveLastRoomPin(room.pin);
      if (mounted) setState(() => _lastRoomPin = room.pin);

      if (mounted) {
        Navigator.pop(context); // dismiss loading
        Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => LobbyScreen(
              room: room,
              playerId: _playerId,
              isHost: true,
            ),
            transitionsBuilder: (_, anim, __, child) {
              return SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(1, 0),
                  end: Offset.zero,
                ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
                child: child,
              );
            },
            transitionDuration: const Duration(milliseconds: 500),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        _showError('Oda oluşturulamadı: $e');
      }
    }
  }

  Future<void> _playSolo() async {
    if (_playerId.isEmpty) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: AppTheme.accentPurple),
      ),
    );
    try {
      final room = await FirebaseService.createRoom(_playerId);
      if (mounted) {
        Navigator.pop(context);
        Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => LobbyScreen(
              room: room,
              playerId: _playerId,
              isHost: true,
              isSolo: true,
            ),
            transitionsBuilder: (_, anim, __, child) => SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(1, 0),
                end: Offset.zero,
              ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
              child: child,
            ),
            transitionDuration: const Duration(milliseconds: 500),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        _showError('Oda oluşturulamadı: $e');
      }
    }
  }

  Future<void> _joinRoom() async {
    if (_playerId.isEmpty) return;
    final pin = _pinController.text.trim();
    if (pin.length != 6) {
      _showError('Lütfen 6 haneli PIN giriniz');
      return;
    }

    setState(() => _isJoining = true);

    try {
      final room = await FirebaseService.findRoomByPin(pin);
      if (room == null) {
        _showError('Bu PIN ile oda bulunamadı');
        setState(() => _isJoining = false);
        return;
      }

      final joined = await FirebaseService.joinRoom(room.roomId, _playerId);
      if (!joined) {
        _showError('Oda dolu veya aktif değil');
        setState(() => _isJoining = false);
        return;
      }

      // PIN'i kaydet — uygulama kapanırsa tekrar girebilsin
      await _saveLastRoomPin(pin);
      if (mounted) setState(() => _lastRoomPin = pin);

      if (mounted) {
        Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => LobbyScreen(
              room: room,
              playerId: _playerId,
              isHost: room.hostId == _playerId,
            ),
            transitionsBuilder: (_, anim, __, child) {
              return SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(1, 0),
                  end: Offset.zero,
                ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
                child: child,
              );
            },
            transitionDuration: const Duration(milliseconds: 500),
          ),
        );
      }
    } catch (e) {
      _showError('Bağlantı hatası: $e');
    } finally {
      if (mounted) setState(() => _isJoining = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFFF85149),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showJoinDialog({String? prefillPin}) {
    _pinController.text = prefillPin ?? '';
    final FocusNode focusNode = FocusNode();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        // Klavyeyi otomatik aç (tablet dahil)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          focusNode.requestFocus();
        });
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Container(
            decoration: const BoxDecoration(
              color: AppTheme.surfaceDark,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              border: Border(
                top: BorderSide(color: AppTheme.borderDark),
                left: BorderSide(color: AppTheme.borderDark),
                right: BorderSide(color: AppTheme.borderDark),
              ),
            ),
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.textMuted,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Odaya Katıl',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Arkadaşının paylaştığı 6 haneli PIN\'i gir',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _pinController,
                  focusNode: focusNode,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: false, signed: false),
                  textInputAction: TextInputAction.done,
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 12,
                    color: AppTheme.textPrimary,
                  ),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: '------',
                    hintStyle: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 12,
                      color: AppTheme.textMuted.withValues(alpha: 0.3),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: AppTheme.greenGradient,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.accentGreen.withValues(alpha: 0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: ElevatedButton(
                      onPressed: _isJoining ? null : () {
                        focusNode.unfocus();
                        Navigator.pop(context);
                        _joinRoom();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: _isJoining
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text(
                              'Katıl',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
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
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                children: [
                  const Spacer(flex: 2),
                  // Animated logo area
                  ScaleTransition(
                    scale: _pulseAnimation,
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        gradient: AppTheme.primaryGradient,
                        borderRadius: BorderRadius.circular(32),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.accentPurple.withValues(alpha: 0.4),
                            blurRadius: 40,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.palette_rounded,
                        size: 60,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  // Title
                  ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [AppTheme.accentPurple, AppTheme.accentBlue],
                    ).createShader(bounds),
                    child: Text(
                      'Color By\nNumber',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        height: 1.1,
                        letterSpacing: -1,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'İki kişilik online boyama deneyimi',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const Spacer(flex: 2),
                  // Create Room Button
                  SizedBox(
                    width: double.infinity,
                    height: 60,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: AppTheme.primaryGradient,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.accentPurple.withValues(alpha: 0.4),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: ElevatedButton.icon(
                        onPressed: _createRoom,
                        icon: const Icon(Icons.add_circle_outline_rounded, color: Colors.white),
                        label: const Text(
                          'Oda Kur',
                          style: TextStyle(
                            fontSize: 18,
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
                  ),
                  const SizedBox(height: 16),
                  // Join Room Button
                  SizedBox(
                    width: double.infinity,
                    height: 60,
                    child: OutlinedButton.icon(
                      onPressed: _showJoinDialog,
                      icon: const Icon(
                        Icons.login_rounded,
                        color: AppTheme.accentBlue,
                      ),
                      label: const Text(
                        'Odaya Katıl',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.accentBlue,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppTheme.accentBlue, width: 2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),
                  ),
                  // Son Oda Geri Dön Banneri
                  if (_lastRoomPin != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.accentPurple.withValues(alpha: 0.4)),
                        color: AppTheme.accentPurple.withValues(alpha: 0.08),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Row(
                        children: [
                          const Icon(Icons.history_rounded, color: AppTheme.accentPurple, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Son oda: $_lastRoomPin',
                                  style: const TextStyle(
                                    color: AppTheme.textPrimary,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                                const Text(
                                  'Kaldığın yere devam et',
                                  style: TextStyle(
                                    color: AppTheme.textMuted,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: () => _showJoinDialog(prefillPin: _lastRoomPin),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              backgroundColor: AppTheme.accentPurple.withValues(alpha: 0.2),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            child: const Text(
                              'Geri Dön',
                              style: TextStyle(
                                color: AppTheme.accentPurple,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: _clearLastRoomPin,
                            icon: const Icon(Icons.close_rounded, color: AppTheme.textMuted, size: 18),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 16),
                  // Solo Play Button
                  SizedBox(
                    width: double.infinity,
                    height: 60,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: AppTheme.greenGradient,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.accentGreen.withValues(alpha: 0.3),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: ElevatedButton.icon(
                        onPressed: _playSolo,
                        icon: const Icon(Icons.person_rounded, color: Colors.white),
                        label: const Text(
                          'Solo Oyna',
                          style: TextStyle(
                            fontSize: 18,
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
                  ),
                  const Spacer(flex: 1),
                  // Footer
                  Text(
                    'Fotoğrafını yükle, boyayı seç, birlikte boya!',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.textMuted,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
      // Banner reklam - ekranın altında
      bottomNavigationBar: _isBannerAdLoaded && AdService.bannerAd != null
          ? SizedBox(
              height: AdSize.banner.height.toDouble(),
              child: AdWidget(ad: AdService.bannerAd!),
            )
          : null,
    );
  }
}
