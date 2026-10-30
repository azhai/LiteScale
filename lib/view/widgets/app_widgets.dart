import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Small caps-ish section label with an optional trailing widget.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.trailing,
    this.top = Insets.section,
  });

  final String title;
  final Widget? trailing;
  final double top;

  @override
  Widget build(BuildContext context) {
    final ThemeData t = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(6, top, 6, 10),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              title,
              style: t.textTheme.labelLarge?.copyWith(
                color: t.colorScheme.onSurfaceVariant,
                letterSpacing: 0.2,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Flat rounded surface — the app's primary container. No elevation, hairline
/// border in light mode, plus a very soft shadow so cards lift off the tinted
/// background without looking heavy.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Insets.card),
    this.color,
    this.gradient,
    this.borderColor,
    this.onTap,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  final Gradient? gradient;
  final Color? borderColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData t = Theme.of(context);
    final ColorScheme cs = t.colorScheme;
    final bool light = t.brightness == Brightness.light;
    final BorderRadius radius = BorderRadius.circular(Radii.card);

    final Widget content = Padding(padding: padding, child: child);

    final Widget body = Container(
      decoration: BoxDecoration(
        color: color ?? (light ? Colors.white : cs.surfaceContainerLow),
        borderRadius: radius,
        border: Border.all(
          color: borderColor ??
              cs.outlineVariant.withValues(alpha: light ? 0.55 : 0.35),
        ),
        boxShadow: light
            ? <BoxShadow>[
                BoxShadow(
                  color: cs.primary.withValues(alpha: 0.05),
                  blurRadius: 22,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: gradient == null
          ? content
          : ClipRRect(
              borderRadius: radius,
              child: DecoratedBox(
                decoration: BoxDecoration(gradient: gradient),
                child: content,
              ),
            ),
    );

    if (onTap == null) return body;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: body,
      ),
    );
  }
}

/// Rounded square tinted icon holder used in list rows.
class IconBadge extends StatelessWidget {
  const IconBadge({
    super.key,
    required this.icon,
    this.tint,
    this.size = 40,
  });

  final IconData icon;
  final Color? tint;
  final double size;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final Color base = tint ?? cs.primary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: base.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(icon, size: size * 0.48, color: base),
    );
  }
}

/// Compact status chip: coloured dot + text, intrinsic width.
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    this.tone,
    this.icon,
  });

  final String label;
  final Color? tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final ThemeData t = Theme.of(context);
    final ColorScheme cs = t.colorScheme;
    final Color base = tone ?? cs.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: base.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(Radii.field),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null)
            Icon(icon, size: 14, color: base)
          else
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: base, shape: BoxShape.circle),
            ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.textTheme.labelMedium?.copyWith(
                color: base,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Label above, big number below. Used in the metric rows.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.color,
    this.align = CrossAxisAlignment.start,
  });

  final String label;
  final String value;
  final String? unit;
  final Color? color;
  final CrossAxisAlignment align;

  @override
  Widget build(BuildContext context) {
    final ThemeData t = Theme.of(context);
    final ColorScheme cs = t.colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: align,
      children: <Widget>[
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: t.textTheme.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 3),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: <Widget>[
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: color ?? cs.onSurface,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ),
            if (unit != null)
              Padding(
                padding: const EdgeInsets.only(left: 2),
                child: Text(
                  unit!,
                  style: t.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Small tappable pill used for member / filter selection.
class ChoicePill extends StatelessWidget {
  const ChoicePill({
    super.key,
    required this.label,
    required this.selected,
    this.onTap,
    this.leading,
    this.trailing,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ThemeData t = Theme.of(context);
    final ColorScheme cs = t.colorScheme;
    final ShapeBorder shape = StadiumBorder(
      side: BorderSide(
        color: selected
            ? cs.primary.withValues(alpha: 0.35)
            : cs.outlineVariant.withValues(alpha: 0.7),
      ),
    );

    final bool light = t.brightness == Brightness.light;
    return Material(
      color: selected
          ? cs.primaryContainer
          : (light ? cs.surfaceContainerLow : cs.surfaceContainerHigh),
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        customBorder: shape,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (leading != null) ...<Widget>[
                leading!,
                const SizedBox(width: 7),
              ],
              Text(
                label,
                style: t.textTheme.labelLarge?.copyWith(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? cs.onPrimaryContainer : cs.onSurface,
                ),
              ),
              if (trailing != null) ...<Widget>[
                const SizedBox(width: 4),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Centred empty state with a soft icon halo.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.text,
    this.action,
  });

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final ThemeData t = Theme.of(context);
    final ColorScheme cs = t.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 44),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 30, color: cs.primary),
          ),
          const SizedBox(height: 16),
          Text(
            text,
            textAlign: TextAlign.center,
            style: t.textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          if (action != null) ...<Widget>[
            const SizedBox(height: 18),
            action!,
          ],
        ],
      ),
    );
  }
}

/// Circular weight gauge: tick dial + track + gradient progress arc.
class WeightRing extends StatelessWidget {
  const WeightRing({
    super.key,
    required this.progress,
    required this.child,
    this.size = 232,
    this.stroke = 13,
  });

  /// 0..1
  final double progress;
  final Widget child;
  final double size;
  final double stroke;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final double target = progress.isNaN ? 0 : progress.clamp(0.0, 1.0);

    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: target),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOutCubic,
        builder: (BuildContext context, double value, Widget? _) {
          return CustomPaint(
            painter: _RingPainter(
              value: value,
              stroke: stroke,
              track: cs.primary.withValues(alpha: 0.09),
              tick: cs.outlineVariant,
              start: cs.primary.withValues(alpha: 0.55),
              end: cs.primary,
            ),
            child: Center(child: child),
          );
        },
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.value,
    required this.stroke,
    required this.track,
    required this.tick,
    required this.start,
    required this.end,
  });

  final double value;
  final double stroke;
  final Color track;
  final Color tick;
  final Color start;
  final Color end;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double outer = math.min(size.width, size.height) / 2;
    final double radius = outer - stroke / 2 - 6;

    // Dial ticks sit just outside the track.
    final Paint tickPaint = Paint()
      ..color = tick.withValues(alpha: 0.55)
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    const int ticks = 60;
    for (int i = 0; i < ticks; i++) {
      final double a = (math.pi * 2 / ticks) * i - math.pi / 2;
      final bool major = i % 5 == 0;
      final double from = radius + stroke / 2 + 3;
      final double len = major ? 5 : 3;
      canvas.drawLine(
        center + Offset(math.cos(a), math.sin(a)) * from,
        center + Offset(math.cos(a), math.sin(a)) * (from + len),
        tickPaint..strokeWidth = major ? 1.4 : 1,
      );
    }

    final Rect arcRect = Rect.fromCircle(center: center, radius: radius);
    final Paint trackPaint = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(arcRect, 0, math.pi * 2, false, trackPaint);

    if (value <= 0.001) return;

    final Paint arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: math.pi * 1.5,
        colors: <Color>[start, end],
        transform: const GradientRotation(-math.pi / 2),
      ).createShader(arcRect);

    canvas.drawArc(arcRect, -math.pi / 2, math.pi * 2 * value, false, arcPaint);

    // Leading dot, slightly inset so the rounded cap lines up.
    final double ang = -math.pi / 2 + math.pi * 2 * value;
    final Offset dot = center + Offset(math.cos(ang), math.sin(ang)) * radius;
    canvas.drawCircle(dot, stroke * 0.22, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value ||
      old.stroke != stroke ||
      old.track != track ||
      old.end != end;
}
