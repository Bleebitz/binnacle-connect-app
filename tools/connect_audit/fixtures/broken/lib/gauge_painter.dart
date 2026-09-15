class GaugePainter {
  void paintStuff(Canvas canvas) {
    final label = TextPainter();
    label.paint(center - Offset(label.width / 2, 0));
  }
}
