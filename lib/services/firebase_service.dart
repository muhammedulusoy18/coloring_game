import 'dart:async';
import 'dart:math';
import 'package:firebase_database/firebase_database.dart';
import 'package:uuid/uuid.dart';
import '../models/game_room.dart';

class FirebaseService {
  static final FirebaseDatabase _db = FirebaseDatabase.instanceFor(
    app: FirebaseDatabase.instance.app,
    databaseURL: 'https://coloring-game-f1292-default-rtdb.europe-west1.firebasedatabase.app',
  );
  static final Uuid _uuid = const Uuid();

  /// Generate a unique device ID
  static String generatePlayerId() {
    return _uuid.v4().substring(0, 8);
  }

  /// Generate a 6-digit PIN
  static String generatePin() {
    final random = Random();
    return (100000 + random.nextInt(900000)).toString();
  }

  /// Create a new game room
  static Future<GameRoom> createRoom(String hostId) async {
    String pin = generatePin();
    String roomId = _uuid.v4().substring(0, 12);

    GameRoom room = GameRoom(
      roomId: roomId,
      pin: pin,
      hostId: hostId,
    );

    await _db.ref('rooms/$roomId').set(room.toJson());
    return room;
  }

  /// Find room by PIN
  static Future<GameRoom?> findRoomByPin(String pin) async {
    final snapshot = await _db.ref('rooms').orderByChild('pin').equalTo(pin).get();
    if (!snapshot.exists || snapshot.value == null) return null;

    final data = snapshot.value as Map<dynamic, dynamic>;
    final firstKey = data.keys.first;
    final roomData = data[firstKey] as Map<dynamic, dynamic>;
    return GameRoom.fromJson(roomData);
  }

  /// Join a room as guest
  static Future<bool> joinRoom(String roomId, String guestId) async {
    final ref = _db.ref('rooms/$roomId');
    final snapshot = await ref.get();
    if (!snapshot.exists) return false;

    final data = snapshot.value as Map<dynamic, dynamic>;
    if (data['guestId'] != null) return false; // Room full
    if (data['status'] != 'waiting') return false;

    await ref.update({
      'guestId': guestId,
    });
    return true;
  }

  /// Upload grid data to Firebase (only palette and grid map, lightweight)
  static Future<void> uploadGridData({
    required String roomId,
    required int width,
    required int height,
    required List<int> palette,
    required Map<String, int> gridData,
  }) async {
    final ref = _db.ref('rooms/$roomId');

    // 1. Upload grid map FIRST
    Map<String, dynamic> gridMap = {};
    gridData.forEach((key, value) {
      gridMap[key] = value;
    });
    await _db.ref('grids/$roomId').set(gridMap);

    // 2. THEN update the room status so the guest can join safely
    await ref.update({
      'gridWidth': width,
      'gridHeight': height,
      'palette': palette,
      'totalCells': width * height,
      'coloredCells': 0,
      'status': 'playing',
    });
  }

  /// Listen for room changes
  static StreamSubscription<DatabaseEvent> listenToRoom(
    String roomId,
    void Function(GameRoom) onUpdate,
  ) {
    return _db.ref('rooms/$roomId').onValue.listen((event) {
      if (event.snapshot.exists && event.snapshot.value != null) {
        final data = event.snapshot.value as Map<dynamic, dynamic>;
        onUpdate(GameRoom.fromJson(data));
      }
    });
  }

  /// Get grid data once
  static Future<Map<String, int>> getGridData(String roomId) async {
    final snapshot = await _db.ref('grids/$roomId').get();
    if (!snapshot.exists || snapshot.value == null) return {};

    Map<String, int> gridData = {};
    final data = snapshot.value as Map<dynamic, dynamic>;
    data.forEach((key, value) {
      gridData[key.toString()] = (value as num).toInt();
    });
    return gridData;
  }

  /// Send a cell color update (ultra-lightweight: only x, y, color, player)
  static Future<void> colorCell({
    required String roomId,
    required int x,
    required int y,
    required int colorIndex,
    required String playerId,
  }) async {
    String cellKey = '${x}_$y';

    // Update cell state
    await _db.ref('cells/$roomId/$cellKey').set({
      'c': colorIndex,
      'p': playerId,
      't': ServerValue.timestamp,
    });

    // Increment colored cells count
    await _db.ref('rooms/$roomId/coloredCells').set(ServerValue.increment(1));
  }

  /// Listen for real-time cell updates from other players
  static StreamSubscription<DatabaseEvent> listenToCellUpdates(
    String roomId,
    void Function(String cellKey, int colorIndex, String playerId) onCellColored,
  ) {
    return _db.ref('cells/$roomId').onChildAdded.listen((event) {
      if (event.snapshot.exists && event.snapshot.value != null) {
        final cellKey = event.snapshot.key!;
        final data = event.snapshot.value as Map<dynamic, dynamic>;
        onCellColored(
          cellKey,
          (data['c'] as num).toInt(),
          data['p']?.toString() ?? '',
        );
      }
    });
  }

  /// Listen for cell changes (updates to existing cells)
  static StreamSubscription<DatabaseEvent> listenToCellChanges(
    String roomId,
    void Function(String cellKey, int colorIndex, String playerId) onCellChanged,
  ) {
    return _db.ref('cells/$roomId').onChildChanged.listen((event) {
      if (event.snapshot.exists && event.snapshot.value != null) {
        final cellKey = event.snapshot.key!;
        final data = event.snapshot.value as Map<dynamic, dynamic>;
        onCellChanged(
          cellKey,
          (data['c'] as num).toInt(),
          data['p']?.toString() ?? '',
        );
      }
    });
  }

  /// Update room status
  static Future<void> updateRoomStatus(String roomId, String status) async {
    await _db.ref('rooms/$roomId/status').set(status);
  }

  /// Delete room and associated data
  static Future<void> deleteRoom(String roomId) async {
    await _db.ref('rooms/$roomId').remove();
    await _db.ref('grids/$roomId').remove();
    await _db.ref('cells/$roomId').remove();
  }

  /// Load all existing cell states for a room
  static Future<Map<String, int>> loadCellStates(String roomId) async {
    final snapshot = await _db.ref('cells/$roomId').get();
    if (!snapshot.exists || snapshot.value == null) return {};

    Map<String, int> states = {};
    final data = snapshot.value as Map<dynamic, dynamic>;
    data.forEach((key, value) {
      if (value is Map) {
        states[key.toString()] = (value['c'] as num).toInt();
      }
    });
    return states;
  }
}
