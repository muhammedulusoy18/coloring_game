import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart';

class AgoraService {
  static const String appId = '9124238526b34c90a44fcc2c6181a75b';
  late RtcEngine _engine;
  bool isJoined = false;
  bool isMuted = false;

  Future<void> initializeAndJoin(String channelName, {required Function(int uid) onUserJoined, required Function(int uid) onUserOffline}) async {
    // 1. Request microphone permission
    await [Permission.microphone].request();

    // 2. Initialize Agora Engine
    _engine = createAgoraRtcEngine();
    await _engine.initialize(const RtcEngineContext(
      appId: appId,
      channelProfile: ChannelProfileType.channelProfileCommunication,
    ));

    // 3. Setup event handlers
    _engine.registerEventHandler(
      RtcEngineEventHandler(
        onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
          print('AGORA: Successfully joined channel ${connection.channelId}');
          isJoined = true;
        },
        onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
          print('AGORA: User joined: $remoteUid');
          onUserJoined(remoteUid);
        },
        onUserOffline: (RtcConnection connection, int remoteUid, UserOfflineReasonType reason) {
          print('AGORA: User offline: $remoteUid');
          onUserOffline(remoteUid);
        },
        onError: (ErrorCodeType err, String msg) {
          print('AGORA ERROR: $err - $msg');
        },
      ),
    );

    // 4. Enable audio and join channel
    await _engine.enableAudio();
    // Using an empty token for testing. Note: If your project enables App Certificate, you MUST generate a token from your server.
    await _engine.joinChannel(
      token: '',
      channelId: channelName,
      uid: 0, // 0 allows Agora to auto-assign a uid
      options: const ChannelMediaOptions(
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
        autoSubscribeAudio: true,
        publishMicrophoneTrack: true,
      ),
    );
  }

  Future<void> toggleMute() async {
    if (isJoined) {
      isMuted = !isMuted;
      await _engine.muteLocalAudioStream(isMuted);
    }
  }

  Future<void> leaveChannel() async {
    if (isJoined) {
      await _engine.leaveChannel();
      await _engine.release();
      isJoined = false;
    }
  }
}
