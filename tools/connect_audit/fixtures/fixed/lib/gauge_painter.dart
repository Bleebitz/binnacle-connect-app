class GaugePainter {
  void paintStuff(Canvas canvas) {
    final label = TextPainter();
    label.paint(canvas, center - Offset(label.width / 2, 0));
  }
}
