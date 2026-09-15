class DeviceListScreen {
  Widget build() {
    return Container(
      decoration: BoxDecoration(color: BinnacleColors.navy),
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(title: Text('x')),
      ),
    );
  }
}
