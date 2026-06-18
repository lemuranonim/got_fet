part of 'got_fet_screen.dart';

class _BatchListItem extends StatelessWidget {
  final _GotFetSample sample;
  final bool selected;
  final Color statusColor;
  final String observationLabel;
  final Color observationColor;
  final String plantingDate;
  final String resultEstimation;
  final String fieldArea;
  final VoidCallback onTap;

  const _BatchListItem({
    super.key,
    required this.sample,
    required this.selected,
    required this.statusColor,
    required this.observationLabel,
    required this.observationColor,
    required this.plantingDate,
    required this.resultEstimation,
    required this.fieldArea,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = _gotFetIsDark(context);
    final borderColor =
        selected ? AdvantaColors.green : _gotFetBorderColor(context);
    final background = selected
        ? AdvantaColors.green.withAlpha(isDark ? 38 : 18)
        : _gotFetCardColor(context);

    return Material(
      color: background,
      borderRadius: AdvantaRadius.cardRadius,
      child: InkWell(
        onTap: onTap,
        borderRadius: AdvantaRadius.cardRadius,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: AdvantaRadius.cardRadius,
            border: Border.all(color: borderColor, width: selected ? 1.6 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: selected
                          ? AdvantaColors.green
                          : AdvantaColors.green.withAlpha(isDark ? 54 : 22),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.tag_rounded,
                      color: selected
                          ? Colors.white
                          : isDark
                              ? Colors.white
                              : AdvantaColors.greenDark,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          sample.batch,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AdvantaText.bodyBold.copyWith(
                            color: _gotFetTextColor(context),
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${sample.hybrid} | ${sample.testType} | ${sample.processStage}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AdvantaText.caption.copyWith(
                            color: _gotFetMutedColor(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _StatusPill(label: sample.status, color: statusColor),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _BatchFact(label: 'Location', value: sample.location),
                  _BatchFact(label: 'Planting', value: plantingDate),
                  _BatchFact(label: 'Result Est.', value: resultEstimation),
                  _BatchFact(
                    label: 'Status Sample',
                    value: sample.statusSample,
                  ),
                  _BatchFact(
                    label: 'Observasi',
                    value: observationLabel,
                    valueColor: observationColor,
                  ),
                  _BatchFact(label: 'Area', value: fieldArea),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    Icons.touch_app_rounded,
                    color: _gotFetMutedColor(context),
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Tap untuk pilih fitur inspeksi',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AdvantaText.caption.copyWith(
                        color: _gotFetMutedColor(context),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.keyboard_arrow_up_rounded,
                    color: _gotFetMutedColor(context),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BatchFact extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _BatchFact({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = _gotFetIsDark(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 104, maxWidth: 158),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withAlpha(9) : AdvantaColors.softGrey,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _gotFetBorderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AdvantaText.caption.copyWith(
              color: _gotFetMutedColor(context),
              fontSize: 10.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AdvantaText.caption.copyWith(
              color: valueColor ?? _gotFetTextColor(context),
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
