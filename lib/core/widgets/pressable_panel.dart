import 'package:flutter/material.dart';

class PressablePanel extends StatefulWidget {
  const PressablePanel({
    super.key,
    required this.child,
    required this.onTap,
    required this.decoration,
    this.padding = EdgeInsets.zero,
    this.borderRadius = 24,
  });

  final Widget child;
  final VoidCallback onTap;
  final BoxDecoration decoration;
  final EdgeInsetsGeometry padding;
  final double borderRadius;

  @override
  State<PressablePanel> createState() => _PressablePanelState();
}

class _PressablePanelState extends State<PressablePanel> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) => AnimatedScale(
    scale: _pressed ? 0.975 : 1,
    duration: const Duration(milliseconds: 115),
    curve: Curves.easeOutCubic,
    child: Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(widget.borderRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        child: Ink(
          decoration: widget.decoration,
          child: Padding(padding: widget.padding, child: widget.child),
        ),
      ),
    ),
  );
}

class ProgressPill extends StatelessWidget {
  const ProgressPill({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.13),
      borderRadius: BorderRadius.circular(30),
      border: Border.all(color: color.withValues(alpha: 0.25)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(color: color, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}
