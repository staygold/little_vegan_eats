// lib/meal_plan/builder/meal_plan_builder_wizard.dart
import 'dart:async';
import 'package:flutter/material.dart';

import '../core/meal_plan_keys.dart';

/// Keep these aligned with your builder screen
const String kAudienceFamily = 'family';
const String kAudienceKids = 'kids';

enum MealPlanWizardMode { program, adhocDay }

class MealPlanDraft {
  // Schedule
  String startDayKey;
  int weeks;
  final Set<int> weekdays;

  // Meals
  bool breakfast;
  bool lunch;
  bool dinner;
  int snacksPerDay;

  // Audiences
  String breakfastAudience;
  String lunchAudience;
  String dinnerAudience;
  String snackAudience;

  // Allergy policy
  bool includeSwaps;

  // Name (program only)
  String planName;

  MealPlanDraft({
    required this.startDayKey,
    this.weeks = 2,
    Set<int>? weekdays,
    this.breakfast = true,
    this.lunch = true,
    this.dinner = true,
    this.snacksPerDay = 1,
    this.breakfastAudience = kAudienceFamily,
    this.lunchAudience = kAudienceFamily,
    this.dinnerAudience = kAudienceFamily,
    this.snackAudience = kAudienceKids,
    this.includeSwaps = true,
    this.planName = '',
  }) : weekdays = weekdays ?? <int>{};
}

/// ✅ Wizard returns focusDayKey on success, null on cancel/fail
typedef WizardSubmit = Future<String?> Function();

class MealPlanWizard extends StatefulWidget {
  const MealPlanWizard({
    super.key,
    required this.mode,
    required this.weekId,
    required this.weekKeys,
    required this.draft,
    required this.onSubmit,
    required this.onClose,
    required this.title,
  });

  final MealPlanWizardMode mode;
  final String weekId;
  final List<String> weekKeys; // current week keys passed in (still used for program schedule UI)

  final MealPlanDraft draft;
  final WizardSubmit onSubmit;

  final VoidCallback onClose;
  final String title;

  @override
  State<MealPlanWizard> createState() => _MealPlanWizardState();
}

class _MealPlanWizardState extends State<MealPlanWizard> {
  int _step = 0;
  bool _submitting = false;

  bool get _isAdhoc => widget.mode == MealPlanWizardMode.adhocDay;

  /// ✅ Adhoc no longer has a schedule step
  int get _totalSteps => _isAdhoc ? 1 : 3;

  void _next() {
    // Program schedule validation
    if (!_isAdhoc && _step == 0) {
      if (widget.draft.weekdays.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select at least one day.')),
        );
        return;
      }
    }

    if (_step >= _totalSteps - 1) return;
    setState(() => _step += 1);
  }

  void _back() {
    if (_step == 0) return;
    setState(() => _step -= 1);
  }

  Future<void> _create() async {
    if (_submitting) return;

    if (!_isAdhoc && widget.draft.planName.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please name your meal plan.')),
      );
      return;
    }

    setState(() => _submitting = true);

    // ✅ push overlay after build frame
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      try {
        final focusKey = await Navigator.of(context).push<String?>(
          PageRouteBuilder(
            opaque: false,
            barrierDismissible: false,
            pageBuilder: (_, __, ___) => MealPlanBuildLoadingScreen(
              mode: widget.mode,
              draft: widget.draft,
              onRun: widget.onSubmit,
            ),
            transitionsBuilder: (_, a, __, child) =>
                FadeTransition(opacity: a, child: child),
          ),
        );

        // ✅ If build succeeded, close wizard and return focus day
        if (!mounted) return;
        if (focusKey != null) {
          Navigator.of(context).pop(focusKey);
        }
      } finally {
        if (mounted) setState(() => _submitting = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // ✅ Page routing with adhoc removing schedule step
    Widget page;

    if (_isAdhoc) {
      // Step 0 = meals/allergy (with date header)
      page = _MealsAllergyStep(draft: widget.draft, showAdhocDateHeader: true);
    } else {
      if (_step == 0) {
        page = _ScheduleStep(
          weekKeys: widget.weekKeys,
          draft: widget.draft,
        );
      } else if (_step == 1) {
        page = _MealsAllergyStep(draft: widget.draft);
      } else {
        page = _NameStep(draft: widget.draft);
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFFECF3F4),
      appBar: AppBar(
        title: Text(widget.title),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _submitting ? null : widget.onClose,
        ),
      ),
      body: Column(
        children: [
          _WizardProgress(step: _step, total: _totalSteps),
          Expanded(child: page),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          decoration: const BoxDecoration(color: Color(0xFF044246)),
          child: Row(
            children: [
              if (!_isAdhoc && _step > 0) ...[
                Expanded(
                  child: _BottomGhostButton(
                    label: 'Back',
                    onTap: _submitting ? null : _back,
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _submitting
                        ? null
                        : (_step == _totalSteps - 1 ? _create : _next),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF32998D),
                      shape: const StadiumBorder(),
                    ),
                    child: Text(
                      (_step == _totalSteps - 1)
                          ? (_isAdhoc ? 'CREATE ONE-OFF DAY' : 'CREATE MEAL PLAN')
                          : 'CONTINUE',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* -------------------- Loading Screen -------------------- */

class MealPlanBuildLoadingScreen extends StatefulWidget {
  const MealPlanBuildLoadingScreen({
    super.key,
    required this.mode,
    required this.draft,
    required this.onRun,
  });

  final MealPlanWizardMode mode;
  final MealPlanDraft draft;
  final WizardSubmit onRun;

  @override
  State<MealPlanBuildLoadingScreen> createState() =>
      _MealPlanBuildLoadingScreenState();
}

class _MealPlanBuildLoadingScreenState extends State<MealPlanBuildLoadingScreen> {
  int _active = 0;
  String? _error;
  Timer? _timer;

  List<String> _stepsText() {
    final isAdhoc = widget.mode == MealPlanWizardMode.adhocDay;
    final startPretty = MealPlanKeys.formatPretty(widget.draft.startDayKey);

    if (isAdhoc) {
      return [
        'Setting up $startPretty',
        'Checking allergies',
        'Finding recipes',
        'Finalising your day',
      ];
    }

    return [
      'Creating schedule',
      'Checking allergies',
      'Finding recipes',
      'Building your plan',
      'Almost done',
    ];
  }

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _run() async {
    final steps = _stepsText();

    // ✅ Slower / more readable
    const perStep = Duration(milliseconds: 900);
    const endHold = Duration(milliseconds: 700);

    final minSequenceTime = perStep * (steps.length - 1);
    final started = DateTime.now();

    _timer = Timer.periodic(perStep, (_) {
      if (!mounted) return;
      setState(() {
        _active = (_active + 1).clamp(0, steps.length - 1);
      });
    });

    try {
      final focusKey = await widget.onRun(); // ✅ String?

      final elapsed = DateTime.now().difference(started);
      if (elapsed < minSequenceTime) {
        await Future.delayed(minSequenceTime - elapsed);
      }

      if (!mounted) return;
      _timer?.cancel();

      // Hold briefly on final state so it doesn't snap away
      await Future.delayed(endHold);
      if (!mounted) return;

      // ✅ Return focus day key (null keeps wizard open)
      Navigator.of(context).pop(focusKey);
    } catch (e) {
      _timer?.cancel();
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final steps = _stepsText();

    return Scaffold(
      backgroundColor: Colors.black.withOpacity(0.35),
      body: Center(
        child: Container(
          width: 340,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: const [
              BoxShadow(
                offset: Offset(0, 12),
                blurRadius: 30,
                color: Color.fromRGBO(0, 0, 0, 0.25),
              )
            ],
          ),
          child: _error != null
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Could not create plan',
                      style:
                          TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _error!,
                      style: TextStyle(color: Colors.black.withOpacity(0.7)),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 44,
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(null),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF044246),
                          shape: const StadiumBorder(),
                        ),
                        child: const Text(
                          'Close',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.mode == MealPlanWizardMode.adhocDay
                          ? 'Creating one-off day'
                          : 'Creating meal plan',
                      style: const TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 16),
                    ),
                    const SizedBox(height: 14),
                    for (int i = 0; i < steps.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            Icon(
                              i < _active
                                  ? Icons.check_circle
                                  : Icons.radio_button_unchecked,
                              size: 18,
                              color: i < _active
                                  ? const Color(0xFF32998D)
                                  : Colors.black.withOpacity(0.25),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                steps[i],
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: i <= _active
                                      ? Colors.black.withOpacity(0.8)
                                      : Colors.black.withOpacity(0.35),
                                ),
                              ),
                            ),
                            if (i == _active)
                              const SizedBox(
                                height: 14,
                                width: 14,
                                child: CircularProgressIndicator(strokeWidth: 2.4),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

/* -------------------- Steps -------------------- */

/// ✅ Program-only schedule step (adhoc no longer uses this)
class _ScheduleStep extends StatefulWidget {
  const _ScheduleStep({
    required this.weekKeys,
    required this.draft,
  });

  final List<String> weekKeys; // current-week keys (from builder screen)
  final MealPlanDraft draft;

  @override
  State<_ScheduleStep> createState() => _ScheduleStepState();
}

class _ScheduleStepState extends State<_ScheduleStep> {
  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  bool _isPastDay(String dayKey) {
    final dt = MealPlanKeys.parseDayKey(dayKey);
    if (dt == null) return true;
    return _dateOnly(dt).isBefore(_dateOnly(DateTime.now()));
  }

  int? _weekdayForDayKey(String dayKey) {
    final dt = MealPlanKeys.parseDayKey(dayKey);
    return dt?.weekday;
  }

  DateTime _startOfWeek(DateTime d) => MealPlanKeys.startOfWeek(_dateOnly(d));

  String _monthShort(int m) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    final idx = (m - 1).clamp(0, 11);
    return months[idx];
  }

  String _weekRangeLabelFromStart(DateTime start) {
    final end = start.add(const Duration(days: 6));
    if (start.month == end.month) {
      return '${start.day}–${end.day} ${_monthShort(start.month)}';
    }
    return '${start.day} ${_monthShort(start.month)}–${end.day} ${_monthShort(end.month)}';
  }

  List<String> _dayKeysForWeekStart(DateTime weekStart) {
    final out = <String>[];
    for (int i = 0; i < 7; i++) {
      out.add(MealPlanKeys.dayKey(weekStart.add(Duration(days: i))));
    }
    return out;
  }

  // Program shows this week + next 4 weeks.
  late final DateTime _baseWeekStart;
  int _weekOffset = 0; // 0..4

  @override
  void initState() {
    super.initState();
    _baseWeekStart = _startOfWeek(DateTime.now());

    // If the draft start day is already in a future week, initialise offset.
    final startDt = MealPlanKeys.parseDayKey(widget.draft.startDayKey);
    if (startDt != null) {
      final startWeek = _startOfWeek(startDt);
      final diffDays = startWeek.difference(_baseWeekStart).inDays;
      final off = (diffDays / 7).round();
      if (off >= 0 && off <= 4) _weekOffset = off;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _ensureValidStartForCurrentWeek();
    });
  }

  void _ensureValidStartForCurrentWeek() {
    final weekStart = _baseWeekStart.add(Duration(days: 7 * _weekOffset));
    final keys = _dayKeysForWeekStart(weekStart);

    final current = widget.draft.startDayKey;
    final currentDt = MealPlanKeys.parseDayKey(current);
    final isCurrentInWeek =
        currentDt != null && _startOfWeek(currentDt) == weekStart;

    if (isCurrentInWeek && !_isPastDay(current)) return;

    for (final dk in keys) {
      if (!_isPastDay(dk)) {
        setState(() => widget.draft.startDayKey = dk);
        return;
      }
    }

    setState(() => widget.draft.startDayKey = keys.last);
  }

  String _weekdayLabel(int w) {
    switch (w) {
      case 1:
        return 'Mon';
      case 2:
        return 'Tue';
      case 3:
        return 'Wed';
      case 4:
        return 'Thu';
      case 5:
        return 'Fri';
      case 6:
        return 'Sat';
      case 7:
        return 'Sun';
      default:
        return '?';
    }
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
        child: Text(text,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
      );

  Widget _card({required Widget child}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [
              BoxShadow(
                offset: Offset(0, 10),
                blurRadius: 24,
                color: Color.fromRGBO(0, 0, 0, 0.08),
              )
            ],
          ),
          child: child,
        ),
      );

  Widget _weekHeaderRow({
    required String weekLabel,
    required bool canPrev,
    required bool canNext,
    required VoidCallback onPrev,
    required VoidCallback onNext,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Previous week',
            icon: Icon(Icons.chevron_left,
                color: Colors.black.withOpacity(canPrev ? 0.8 : 0.25)),
            onPressed: canPrev ? onPrev : null,
          ),
          Expanded(
            child: Text(
              weekLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
              textAlign: TextAlign.center,
            ),
          ),
          IconButton(
            tooltip: 'Next week',
            icon: Icon(Icons.chevron_right,
                color: Colors.black.withOpacity(canNext ? 0.8 : 0.25)),
            onPressed: canNext ? onNext : null,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.draft;

    final weekStart = _baseWeekStart.add(Duration(days: 7 * _weekOffset));
    final weekLabel = _weekRangeLabelFromStart(weekStart);
    final keys = _dayKeysForWeekStart(weekStart);

    final canPrev = _weekOffset > 0;
    final canNext = _weekOffset < 4;

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _sectionTitle('START DATE'),
        _card(
          child: Column(
            children: [
              _weekHeaderRow(
                weekLabel: weekLabel,
                canPrev: canPrev,
                canNext: canNext,
                onPrev: () {
                  setState(() => _weekOffset = (_weekOffset - 1).clamp(0, 4));
                  _ensureValidStartForCurrentWeek();
                },
                onNext: () {
                  setState(() => _weekOffset = (_weekOffset + 1).clamp(0, 4));
                  _ensureValidStartForCurrentWeek();
                },
              ),
              const Divider(height: 10),
              Column(
                children: keys.map((dk) {
                  final disabled = _isPastDay(dk);
                  final selected = d.startDayKey == dk;
                  final fg =
                      !disabled ? Colors.black : Colors.black.withOpacity(0.35);

                  return InkWell(
                    onTap: disabled
                        ? null
                        : () {
                            setState(() {
                              d.startDayKey = dk;

                              // If user hasn't picked weekdays yet, auto-add the weekday of start date
                              if (d.weekdays.isEmpty) {
                                final wd = _weekdayForDayKey(dk);
                                if (wd != null) d.weekdays.add(wd);
                              }
                            });
                          },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Icon(
                            selected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                            color: selected
                                ? const Color(0xFF32998D)
                                : Colors.black.withOpacity(0.35),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              MealPlanKeys.formatPretty(dk),
                              style: TextStyle(
                                  fontWeight: FontWeight.w800, color: fg),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        _sectionTitle('DAYS'),
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Choose the days you want meals planned (e.g. Mon/Wed/Fri).',
                style: TextStyle(
                  color: Colors.black.withOpacity(0.55),
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(7, (i) {
                  final w = i + 1;
                  final selected = d.weekdays.contains(w);
                  return _ChipToggle(
                    label: _weekdayLabel(w),
                    selected: selected,
                    onTap: () {
                      setState(() {
                        if (selected) {
                          d.weekdays.remove(w);
                        } else {
                          d.weekdays.add(w);
                        }
                      });
                    },
                  );
                }),
              ),
              const SizedBox(height: 8),
              Text(
                'Tip: most people pick 3–5 days.',
                style: TextStyle(
                  color: Colors.black.withOpacity(0.50),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        _sectionTitle('LENGTH'),
        _card(
          child: Row(
            children: [1, 2, 3, 4].map((n) {
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: n == 4 ? 0 : 10),
                  child: _SegButton(
                    label: '$n wk',
                    selected: d.weeks == n,
                    onTap: () => setState(() => d.weeks = n),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _MealsAllergyStep extends StatefulWidget {
  const _MealsAllergyStep({
    required this.draft,
    this.showAdhocDateHeader = false,
  });

  final MealPlanDraft draft;

  /// ✅ When true, shows "ONE-OFF DAY • <date>" above the controls
  final bool showAdhocDateHeader;

  @override
  State<_MealsAllergyStep> createState() => _MealsAllergyStepState();
}

class _MealsAllergyStepState extends State<_MealsAllergyStep> {
  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
        child: Text(text,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
      );

  Widget _card({required Widget child}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [
              BoxShadow(
                offset: Offset(0, 10),
                blurRadius: 24,
                color: Color.fromRGBO(0, 0, 0, 0.08),
              )
            ],
          ),
          child: child,
        ),
      );

  Widget _adhocHeader() {
    final pretty = MealPlanKeys.formatPretty(widget.draft.startDayKey);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(
              offset: Offset(0, 10),
              blurRadius: 24,
              color: Color.fromRGBO(0, 0, 0, 0.06),
            )
          ],
        ),
        child: Row(
          children: [
            Icon(Icons.event, size: 18, color: Colors.black.withOpacity(0.55)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'ONE-OFF DAY  •  $pretty',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.25,
                  color: Colors.black.withOpacity(0.78),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.draft;

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (widget.showAdhocDateHeader) _adhocHeader(),
        _sectionTitle('MEALS'),
        _card(
          child: Column(
            children: [
              _ToggleRow(
                title: 'Breakfast',
                value: d.breakfast,
                onChanged: (v) => setState(() => d.breakfast = v),
              ),
              if (d.breakfast) ...[
                const SizedBox(height: 8),
                _AudienceRow(
                  title: 'For',
                  value: d.breakfastAudience,
                  onChanged: (v) => setState(() => d.breakfastAudience = v),
                ),
              ],
              const Divider(height: 18),
              _ToggleRow(
                title: 'Lunch',
                value: d.lunch,
                onChanged: (v) => setState(() => d.lunch = v),
              ),
              if (d.lunch) ...[
                const SizedBox(height: 8),
                _AudienceRow(
                  title: 'For',
                  value: d.lunchAudience,
                  onChanged: (v) => setState(() => d.lunchAudience = v),
                ),
              ],
              const Divider(height: 18),
              _ToggleRow(
                title: 'Family dinner',
                value: d.dinner,
                onChanged: (v) => setState(() => d.dinner = v),
              ),
              if (d.dinner) ...[
                const SizedBox(height: 8),
                _AudienceRow(
                  title: 'For',
                  value: d.dinnerAudience,
                  onChanged: (v) => setState(() => d.dinnerAudience = v),
                ),
              ],
            ],
          ),
        ),
        _sectionTitle('SNACKS PER DAY'),
        _card(
          child: Row(
            children: [0, 1, 2].map((n) {
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: n == 2 ? 0 : 10),
                  child: _SegButton(
                    label: '$n',
                    selected: d.snacksPerDay == n,
                    onTap: () => setState(() => d.snacksPerDay = n),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        if (d.snacksPerDay > 0) ...[
          _sectionTitle('SNACKS ARE FOR'),
          _card(
            child: _AudienceRow(
              title: 'Snacks',
              value: d.snackAudience,
              onChanged: (v) => setState(() => d.snackAudience = v),
            ),
          ),
        ],
        _sectionTitle('ALLERGY SETTINGS'),
        _card(
          child: Column(
            children: [
              _ToggleRow(
                title: 'Include recipes that need swaps',
                value: d.includeSwaps,
                onChanged: (v) => setState(() => d.includeSwaps = v),
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Allows recipes that require ingredient replacements to be safe.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.black.withOpacity(0.5),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NameStep extends StatefulWidget {
  const _NameStep({required this.draft});
  final MealPlanDraft draft;

  @override
  State<_NameStep> createState() => _NameStepState();
}

class _NameStepState extends State<_NameStep> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.draft.planName);
    _ctrl.addListener(() => widget.draft.planName = _ctrl.text);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
        child: Text(text,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
      );

  Widget _card({required Widget child}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [
              BoxShadow(
                offset: Offset(0, 10),
                blurRadius: 24,
                color: Color.fromRGBO(0, 0, 0, 0.08),
              )
            ],
          ),
          child: child,
        ),
      );

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _sectionTitle('PLAN NAME'),
        _card(
          child: TextField(
            controller: _ctrl,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'e.g. School nights',
              border: InputBorder.none,
            ),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        Padding(
  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
  
),

// ✅ Nutrition disclaimer (Option A) – sits just above the bottom bar CTA
Padding(
  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
  child: Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Colors.black.withOpacity(0.06)),
      boxShadow: const [
        BoxShadow(
          offset: Offset(0, 10),
          blurRadius: 24,
          color: Color.fromRGBO(0, 0, 0, 0.06),
        )
      ],
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline, size: 18, color: Colors.black.withOpacity(0.55)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            "Please note: Meal plans are suggestions only and aren’t designed to meet individual nutritional requirements. Always review recipes and adjust for your family.",
            style: TextStyle(
              height: 1.25,
              color: Colors.black.withOpacity(0.62),
              fontWeight: FontWeight.w600,
              fontSize: 12.5,
            ),
          ),
        ),
      ],
    ),
  ),
),

// Little spacer so it doesn't feel jammed against the bottom bar
const SizedBox(height: 10),
      ],
    );
  }
}

/* -------------------- Progress + Buttons -------------------- */

class _WizardProgress extends StatelessWidget {
  const _WizardProgress({required this.step, required this.total});
  final int step;
  final int total;

  @override
  Widget build(BuildContext context) {
    final pct = (step + 1) / total;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 8,
              backgroundColor: Colors.black.withOpacity(0.08),
              valueColor: const AlwaysStoppedAnimation(Color(0xFF32998D)),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Step ${step + 1} of $total',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: Colors.black.withOpacity(0.55),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomGhostButton extends StatelessWidget {
  const _BottomGhostButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: BorderSide(color: Colors.white.withOpacity(0.35)),
          shape: const StadiumBorder(),
        ),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
      ),
    );
  }
}

/* -------------------- Atoms -------------------- */

class _SegButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SegButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF044246) : const Color(0xFFF1F5F6),
          borderRadius: BorderRadius.circular(999),
        ),
        alignment: Alignment.center,
        child: Text(
          label.toUpperCase(),
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 12,
            letterSpacing: 0.35,
            color: selected ? Colors.white : Colors.black.withOpacity(0.65),
          ),
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title,
              style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}

class _ChipToggle extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ChipToggle({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF044246) : const Color(0xFFF1F5F6),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label.toUpperCase(),
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 12,
            letterSpacing: 0.35,
            color: selected ? Colors.white : Colors.black.withOpacity(0.65),
          ),
        ),
      ),
    );
  }
}

class _AudienceRow extends StatelessWidget {
  final String title;
  final String value;
  final ValueChanged<String> onChanged;

  const _AudienceRow({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: Colors.black.withOpacity(0.7),
            ),
          ),
        ),
        _AudienceChip(
          label: 'Family',
          selected: value == kAudienceFamily,
          onTap: () => onChanged(kAudienceFamily),
        ),
        const SizedBox(width: 8),
        _AudienceChip(
          label: 'Kids',
          selected: value == kAudienceKids,
          onTap: () => onChanged(kAudienceKids),
        ),
      ],
    );
  }
}

class _AudienceChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _AudienceChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF044246) : const Color(0xFFF1F5F6),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label.toUpperCase(),
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 11,
            letterSpacing: 0.3,
            color: selected ? Colors.white : Colors.black.withOpacity(0.6),
          ),
        ),
      ),
    );
  }
}
