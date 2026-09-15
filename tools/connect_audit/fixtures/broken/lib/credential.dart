class DeviceCredential {
  String? bearerToken;
  void debug() {
    print('token=$bearerToken');
  }
  Map<String, dynamic> toJsonSafe() => {'bearerToken': bearerToken};
}
