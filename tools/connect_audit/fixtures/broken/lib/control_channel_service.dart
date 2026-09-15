const Set<String> kNoDisableCommands = {
  'set_fall_detection',
  'set_mob_alert',
  'disable_safety',
};

class ControlChannelService {
  String sendCommand(String command, Map<String, dynamic> params) {
    if (kNoDisableCommands.contains(command)) {
      throw CommandRejected('safety_not_disableable');
    }
    final id = 'c-${_uuid.v4()}';
    return id;
  }
}
