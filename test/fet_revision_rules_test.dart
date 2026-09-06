import 'package:flutter_test/flutter_test.dart';
import 'package:kroscek_got_fet/domain/fet_revision_rules.dart';

void main() {
  test('FET exposes Day 7 and Day 11 observations', () {
    expect(FetRevisionRules.observationDays, [7, 11]);
    expect(FetRevisionRules.slotKey(day: 7, replication: 1), 71);
    expect(FetRevisionRules.slotKey(day: 11, replication: 2), 112);
  });

  test('each observation day and replication has a separate slot', () {
    final slots = <int>{
      for (final day in FetRevisionRules.observationDays)
        for (final replication in const [1, 2])
          FetRevisionRules.slotKey(day: day, replication: replication),
    };
    expect(slots, {71, 72, 111, 112});
  });

  test('FET remarks options are fixed', () {
    expect(FetRevisionRules.remarkOptions, ['Retest', 'Resampling', 'Done']);
  });

  test('watermark explicitly labels Lot and Ulangan', () {
    expect(
      FetRevisionRules.watermarkLines(lotId: 'LOT-001', replication: 2),
      ['Lot: LOT-001', 'Ulangan: 2'],
    );
  });

  test('FET result estimation is planting date plus 12 days', () {
    expect(
      FetRevisionRules.resultEstimation(DateTime(2026, 7, 31)),
      DateTime(2026, 8, 12),
    );
  });

  test('lot status stays in progress until all four slots are complete', () {
    expect(
      FetRevisionRules.lotProgressStatus(
        completedSlots: 3,
        hasActionRequired: false,
      ),
      'FET In Progress (3/4)',
    );
    expect(
      FetRevisionRules.lotProgressStatus(
        completedSlots: 4,
        hasActionRequired: false,
      ),
      'FET Observation Complete',
    );
  });
}
