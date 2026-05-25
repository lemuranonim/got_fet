import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class GotFetCircularProgress extends StatelessWidget {
  final double progress;
  final double size;
  final String? centerText;
  final Color? color;

  const GotFetCircularProgress({
    super.key,
    required this.progress,
    this.size = 118,
    this.centerText,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeColor = color ?? AdvantaColors.green;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: progress.clamp(0, 1),
              strokeWidth: 9,
              strokeCap: StrokeCap.round,
              backgroundColor:
                  isDark ? Colors.white.withAlpha(28) : AdvantaColors.lineLight,
              color: activeColor,
            ),
          ),
          Text(
            centerText ?? '${(progress * 100).round()}%',
            style: AdvantaText.heading1.copyWith(
              color: isDark ? Colors.white : AdvantaColors.navy,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class GotFetPulsingDots extends StatefulWidget {
  final double size;

  const GotFetPulsingDots({super.key, this.size = 8});

  @override
  State<GotFetPulsingDots> createState() => _GotFetPulsingDotsState();
}

class _GotFetPulsingDotsState extends State<GotFetPulsingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const colors = [
      AdvantaColors.navy,
      AdvantaColors.blue,
      AdvantaColors.green,
      Color(0xFF7DDC8A),
    ];

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < colors.length; i++) ...[
              Transform.scale(
                scale: 0.72 + (_dotWave(i) * 0.42),
                child: Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    color: colors[i],
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              if (i != colors.length - 1) SizedBox(width: widget.size),
            ],
          ],
        );
      },
    );
  }

  double _dotWave(int index) {
    final shifted = (_controller.value + index * .16) % 1;
    return shifted < .5 ? shifted * 2 : (1 - shifted) * 2;
  }
}

class GotFetStepProgress extends StatelessWidget {
  final List<String> steps;
  final int activeIndex;

  const GotFetStepProgress({
    super.key,
    required this.steps,
    required this.activeIndex,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted =
        isDark ? AdvantaColors.textMutedDark : AdvantaColors.textMuted;

    return Row(
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i < activeIndex
                        ? AdvantaColors.green
                        : i == activeIndex
                            ? AdvantaColors.navy
                            : (isDark
                                ? Colors.white.withAlpha(18)
                                : AdvantaColors.lineLight),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    i < activeIndex
                        ? Icons.check_rounded
                        : i == activeIndex
                            ? Icons.radio_button_checked_rounded
                            : Icons.more_horiz_rounded,
                    size: 16,
                    color: i <= activeIndex ? Colors.white : muted,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  steps[i],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: AdvantaText.caption.copyWith(
                    color: i <= activeIndex
                        ? (isDark ? Colors.white : AdvantaColors.navy)
                        : muted,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          if (i != steps.length - 1)
            Expanded(
              child: Container(
                height: 2,
                margin: const EdgeInsets.only(bottom: 26),
                color: i < activeIndex
                    ? AdvantaColors.green
                    : (isDark
                        ? Colors.white.withAlpha(22)
                        : AdvantaColors.lineLight),
              ),
            ),
        ],
      ],
    );
  }
}

class GotFetSkeletonList extends StatelessWidget {
  final int itemCount;

  const GotFetSkeletonList({super.key, this.itemCount = 4});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < itemCount; i++) ...[
          _SkeletonCard(index: i),
          if (i != itemCount - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  final int index;

  const _SkeletonCard({required this.index});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fill = isDark ? Colors.white.withAlpha(16) : const Color(0xFFE7EDF5);
    final fillStrong =
        isDark ? Colors.white.withAlpha(26) : const Color(0xFFDDE5EF);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AdvantaColors.darkSurface : Colors.white,
        borderRadius: AdvantaRadius.cardRadius,
        border: Border.all(
          color: isDark ? AdvantaColors.lineDark : AdvantaColors.lineLight,
        ),
        boxShadow: AdvantaShadows.card(isDark),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: fillStrong,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FractionallySizedBox(
                  widthFactor: .78 - (index % 2) * .16,
                  child: _SkeletonBar(color: fillStrong, height: 10),
                ),
                const SizedBox(height: 9),
                FractionallySizedBox(
                  widthFactor: .56 + (index % 2) * .12,
                  child: _SkeletonBar(color: fill, height: 8),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SkeletonBar extends StatelessWidget {
  final Color color;
  final double height;

  const _SkeletonBar({required this.color, required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}

class GotFetOverlayLoader extends StatelessWidget {
  final String title;
  final String message;
  final double progress;

  const GotFetOverlayLoader({
    super.key,
    required this.title,
    required this.message,
    this.progress = .72,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ColoredBox(
      color: Colors.black.withAlpha(isDark ? 150 : 92),
      child: Center(
        child: Container(
          width: 286,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AdvantaColors.navy,
                AdvantaColors.navyDeep,
              ],
            ),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withAlpha(34)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(90),
                blurRadius: 28,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/logo_got_fet_unbox.png',
                width: 78,
                height: 48,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 10),
              Text(
                title,
                textAlign: TextAlign.center,
                style: AdvantaText.bodyBold.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 5),
              Text(
                message,
                textAlign: TextAlign.center,
                style: AdvantaText.caption.copyWith(
                  color: Colors.white.withAlpha(185),
                ),
              ),
              const SizedBox(height: 15),
              LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                borderRadius: BorderRadius.circular(999),
                backgroundColor: Colors.white.withAlpha(22),
                color: AdvantaColors.green,
              ),
              const SizedBox(height: 14),
              const GotFetPulsingDots(size: 7),
            ],
          ),
        ),
      ),
    );
  }
}
