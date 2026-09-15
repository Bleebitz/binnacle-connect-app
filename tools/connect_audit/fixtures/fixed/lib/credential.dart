class DeviceCredential {
  String? bearerToken;
  void debug() {
    print('credential_id=$credentialId');
  }
  Map<String, dynamic> toJsonSafe() => {'credential_id': credentialId};
}
