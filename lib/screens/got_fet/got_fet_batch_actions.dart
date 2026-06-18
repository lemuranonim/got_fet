part of 'got_fet_screen.dart';

class _BatchQuickAction {
  final String label;
  final String subtitle;
  final IconData icon;
  final _GotFetPage page;
  final _GotObservationStage? stage;
  final int? reviewSegment;

  const _BatchQuickAction({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.page,
    this.stage,
    this.reviewSegment,
  });
}

class _BatchQuickActionSheet extends StatelessWidget {
  final _GotFetSample sample;
  final String module;
  final List<_BatchQuickAction> actions;
  final ValueChanged<_BatchQuickAction> onAction;

  const _BatchQuickActionSheet({
    required this.sample,
    required this.module,
    required this.actions,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final logoAsset =
        module == 'FET' ? _GotFetAssets.fetLogo : _GotFetAssets.gotLogo;
    final title = module == 'FET' ? 'Aksi Batch FET' : 'Aksi Batch GOT';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ModuleStrip(
            logoAsset: logoAsset,
            title: title,
            subtitle: '${sample.batch} | ${sample.hybrid}',
          ),
          const SizedBox(height: 12),
          for (final action in actions) ...[
            _BatchQuickActionTile(
              action: action,
              onTap: () => onAction(action),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _BatchQuickActionTile extends StatelessWidget {
  final _BatchQuickAction action;
  final VoidCallback onTap;

  const _BatchQuickActionTile({
    required this.action,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = _gotFetIsDark(context);

    return Material(
      color: _gotFetCardColor(context),
      borderRadius: AdvantaRadius.cardRadius,
      child: InkWell(
        onTap: onTap,
        borderRadius: AdvantaRadius.cardRadius,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: AdvantaRadius.cardRadius,
            border: Border.all(color: _gotFetBorderColor(context)),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AdvantaColors.green.withAlpha(isDark ? 54 : 22),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  action.icon,
                  color: isDark ? Colors.white : AdvantaColors.greenDark,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      action.label,
                      style: AdvantaText.bodyBold.copyWith(
                        color: _gotFetTextColor(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      action.subtitle,
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
              Icon(
                Icons.chevron_right_rounded,
                color: _gotFetMutedColor(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
