@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:litescale/model/entities.dart';
import 'package:litescale/model/weight_record.dart';
import 'package:litescale/service/app_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('height and goals belong to each member', () async {
    final AppController app = AppController();
    await app.init();
    final Member a = await app.addMember('A');
    final Member b = await app.addMember('B');

    await app.setHeightCm(170, memberId: a.id);
    await app.setHeightCm(180, memberId: b.id);
    expect(app.heightCmOf(a.id), 170);
    expect(app.heightCmOf(b.id), 180);
    expect(app.bmiOf(70, memberId: a.id), closeTo(70 / (1.7 * 1.7), 1e-9));

    final String today = AppController.dayKey(DateTime.now());
    final String past =
        AppController.dayKey(DateTime.now().subtract(const Duration(days: 10)));
    final String future =
        AppController.dayKey(DateTime.now().add(const Duration(days: 10)));
    await app.setMemberGoal(MemberGoal(date: past, targetKg: 75), memberId: a.id);
    await app.setMemberGoal(MemberGoal(date: future, targetKg: 68), memberId: a.id);
    await app.setMemberGoal(MemberGoal(date: today, targetKg: 65), memberId: b.id);

    expect(app.goalFor(a.id)?.date, future);
    expect(app.goalFor(b.id)?.date, today);
    expect(app.goalFor(b.id)?.targetKg, 65);

    // Same date replaces instead of appending.
    await app.setMemberGoal(MemberGoal(date: future, targetKg: 67), memberId: a.id);
    Member memberA = app.members.firstWhere((Member m) => m.id == a.id);
    expect(memberA.goals, hasLength(2));
    expect(memberA.goals.last.targetKg, 67);

    await app.removeMemberGoal(future, memberId: a.id);
    expect(app.goalFor(a.id)?.date, past);
  });

  test('goal actual weight is the last record of that local day', () async {
    final AppController app = AppController();
    await app.init();
    final Member a = await app.addMember('A');
    final Member b = await app.addMember('B');

    await app.importRecords(<WeightRecord>[
      WeightRecord(time: DateTime(2026, 10, 28, 9), kg: 72.0, memberId: a.id),
      WeightRecord(time: DateTime(2026, 10, 29, 8, 10), kg: 71.2, memberId: a.id),
      WeightRecord(time: DateTime(2026, 10, 29, 21, 5), kg: 70.4, memberId: a.id),
      WeightRecord(time: DateTime(2026, 10, 29, 20), kg: 60.0, memberId: b.id),
    ]);

    expect(app.goalActualKg('2026-10-29', memberId: a.id), 70.4);
    expect(app.goalActualKg('2026-10-28', memberId: a.id), 72.0);
    expect(app.goalActualKg('2026-10-29', memberId: b.id), 60.0);
    expect(app.goalActualKg('2026-10-27', memberId: a.id), isNull);
  });

  test('gender and birth month persist per member and can be cleared', () async {
    final AppController app = AppController();
    await app.init();
    final Member a = await app.addMember('A');
    final Member b = await app.addMember('B');

    await app.setMemberDetails(a.id, gender: 'female', birth: '1990-05');
    await app.setMemberDetails(b.id, gender: 'male', birth: '1985-11');
    Member memberA = app.members.firstWhere((Member m) => m.id == a.id);
    Member memberB = app.members.firstWhere((Member m) => m.id == b.id);
    expect(memberA.gender, 'female');
    expect(memberA.birth, '1990-05');
    expect(memberB.gender, 'male');
    expect(memberB.birth, '1985-11');

    // Reload from storage: the fields survive the JSON round trip.
    final AppController reloaded = AppController();
    await reloaded.init();
    memberA = reloaded.members.firstWhere((Member m) => m.id == a.id);
    expect(memberA.gender, 'female');
    expect(memberA.birth, '1990-05');

    await app.setMemberDetails(a.id, gender: '', birth: '');
    memberA = app.members.firstWhere((Member m) => m.id == a.id);
    expect(memberA.gender, isEmpty);
    expect(memberA.birth, isEmpty);
  });

  test('legacy global height and goal move to the active member', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'heightCm': 168.0,
      'goalKg': 64.0,
    });
    final AppController app = AppController();
    await app.init();

    expect(app.heightCmOf(), 168);
    final MemberGoal? goal = app.activeGoal;
    expect(goal, isNotNull);
    expect(goal!.targetKg, 64);
    expect(goal.date, AppController.dayKey(DateTime.now()));

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('heightCm'), isFalse);
    expect(prefs.containsKey('goalKg'), isFalse);
  });
}
