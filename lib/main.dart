import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'exec_questions.dart';
import 'legal_pages.dart';
import 'purchase_manager.dart';

DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

// AdMobがサポートするプラットフォームで、かつ広告非表示を購入していないかどうか
bool get _adsSupported =>
    !kIsWeb && (Platform.isIOS || Platform.isAndroid) && !adsRemovedNotifier.value;

// 問題演習のインタースティシャル広告ユニットID
// TODO: Android版もリリースする場合は、Android用に別途発行した広告ユニットIDに差し替えること。
// (AdMobではiOS/Androidそれぞれ別アプリとして登録し、別々のIDが発行される)
String get _interstitialAdUnitId {
  if (Platform.isIOS) {
    return 'ca-app-pub-3050514564102147/5448841171'; // 本番ID(iOS)
  }
  return 'ca-app-pub-3940256099942544/1033173712'; // テスト用ID(Android・未設定)
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PurchaseManager.init();
  runApp(const Joho1App());
}

// ATTの許諾状態を確認し、未確認なら許諾ダイアログを表示してから
// 広告SDKを初期化する。iOS以外(Android等)ではATT許諾を経ずに直接初期化する。
Future<void> _requestTrackingAndInitAds() async {
  if (!_adsSupported) return;
  if (Platform.isIOS) {
    final status = await AppTrackingTransparency.trackingAuthorizationStatus;
    if (status == TrackingStatus.notDetermined) {
      // ダイアログがアプリ表示直後に出て見逃されるのを避けるための短い待機
      await Future.delayed(const Duration(milliseconds: 300));
      await AppTrackingTransparency.requestTrackingAuthorization();
    }
  }
  await MobileAds.instance.initialize();
}

// _requestTrackingAndInitAds()は一度だけ実行すればよいため、
// 結果のFutureをキャッシュして他の画面から広告SDKの初期化完了を待てるようにする。
Future<void>? _adsInitFuture;

Future<void> _ensureAdsInitialized() {
  return _adsInitFuture ??= _requestTrackingAndInitAds();
}

// ============================================================
// Models
// ============================================================


class ProgressData {
  final int correctCount;
  final int answeredCount;
  const ProgressData({
    this.correctCount = 0,
    this.answeredCount = 0,
  });

  double get accuracy =>
      answeredCount == 0 ? 0.0 : correctCount / answeredCount;

  int get studyMinutes => answeredCount; // 1問 ≒ 1分の概算

  ProgressData addSession(int correct, int total) {
    if (total == 0) return this;
    return ProgressData(
      correctCount: correctCount + correct,
      answeredCount: answeredCount + total,
    );
  }
}



// ============================================================
// App
// ============================================================

const _kPrimary = Color(0xFF4361EE);
const _kBg = Color(0xFFF0F4FF);

class Joho1App extends StatelessWidget {
  const Joho1App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '情報Ⅰ プログラミング対策',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: _kPrimary),
        useMaterial3: true,
        scaffoldBackgroundColor: _kBg,
      ),
      home: const HomePage(),
    );
  }
}

// ============================================================
// Home Page (with bottom navigation)
// ============================================================

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final List<ExecQuestion> _wrongExecQuestions = [];
  final List<ExecQuestion> _bookmarkedExecQuestions = [];
  ProgressData _progress = const ProgressData();

  static const int _dailyGoal = 10;
  int _dailyAnswered = 0;
  DateTime _today = _dateOnly(DateTime.now());
  // Blocks pointer events during exec-practice exit animation to prevent
  // re-entrant MouseTracker._deviceUpdatePhase assertion on Windows.
  bool _blockPointerEvents = false;

  void _checkDayReset() {
    final now = _dateOnly(DateTime.now());
    if (now.isAfter(_today)) {
      setState(() {
        _today = now;
        _dailyAnswered = 0;
      });
    }
  }

  static const _prefKeyWrongExec = 'wrong_exec_questions';

  Future<void> _loadWrongExecQuestions() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKeyWrongExec);
    if (raw == null) return;
    final list = jsonDecode(raw) as List<dynamic>;
    final loaded = <ExecQuestion>[];
    for (final item in list) {
      final code = item['code'] as String?;
      ExecQuestion? q;
      if (code != null) {
        q = kExecQuestions.where((q) => q.code == code).firstOrNull;
      } else {
        final qt = item['questionText'] as String?;
        if (qt != null) q = kExecQuestions.where((q) => q.questionText == qt).firstOrNull;
      }
      if (q != null && !loaded.contains(q)) loaded.add(q);
    }
    if (mounted && loaded.isNotEmpty) {
      setState(() => _wrongExecQuestions.addAll(loaded));
    }
  }

  Future<void> _saveWrongExecQuestions() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _wrongExecQuestions.map((q) => {'code': q.code}).toList();
    await prefs.setString(_prefKeyWrongExec, jsonEncode(list));
  }

  static const _prefKeyBookmarked = 'bookmarked_exec_questions';

  Future<void> _loadBookmarkedExecQuestions() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKeyBookmarked);
    if (raw == null) return;
    final list = jsonDecode(raw) as List<dynamic>;
    final loaded = <ExecQuestion>[];
    for (final item in list) {
      final code = item['code'] as String?;
      ExecQuestion? q;
      if (code != null) {
        q = kExecQuestions.where((q) => q.code == code).firstOrNull;
      } else {
        final qt = item['questionText'] as String?;
        if (qt != null) q = kExecQuestions.where((q) => q.questionText == qt).firstOrNull;
      }
      if (q != null && !loaded.contains(q)) loaded.add(q);
    }
    if (mounted && loaded.isNotEmpty) {
      setState(() => _bookmarkedExecQuestions.addAll(loaded));
    }
  }

  Future<void> _saveBookmarkedExecQuestions() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _bookmarkedExecQuestions.map((q) => {'code': q.code}).toList();
    await prefs.setString(_prefKeyBookmarked, jsonEncode(list));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadWrongExecQuestions();
    _loadBookmarkedExecQuestions();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureAdsInitialized();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkDayReset();
      PurchaseManager.refreshStatus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AbsorbPointer(
      absorbing: _blockPointerEvents,
      child: Scaffold(
        backgroundColor: _kBg,
        appBar: _buildAppBar(),
        body: _buildHomeTab(),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: _kBg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleSpacing: 16,
      title: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _kPrimary,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.code, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '情報Ⅰ プログラミング対策',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A2E),
                  letterSpacing: -0.3,
                ),
              ),
              Text(
                '共通テスト対策',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.settings_outlined, color: Color(0xFF1A1A2E)),
          onPressed: _openSettings,
        ),
      ],
    );
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsPage()),
    );
  }

  // ---- Tabs ----

  void _navigateToWrongExecQuiz() async {
    if (_wrongExecQuestions.isEmpty) return;
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final snapshot = List<ExecQuestion>.from(_wrongExecQuestions)..shuffle();
    final result = await nav.push<(List<ExecQuestion>, int, int, List<ExecQuestion>, List<ExecQuestion>)?>(
      MaterialPageRoute(
        builder: (_) => ExecutionPracticePage(questions: snapshot),
      ),
    );
    if (!mounted || result == null) return;
    setState(() { _blockPointerEvents = true; });
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;
    final (_, correct, total, bookmarked, correctlyAnswered) = result;
    _checkDayReset();
    setState(() {
      _blockPointerEvents = false;
      _progress = _progress.addSession(correct, total);
      _dailyAnswered += total;
      final correctCodes = correctlyAnswered.map((q) => q.code).toSet();
      _wrongExecQuestions.removeWhere((q) => correctCodes.contains(q.code));
    });
    _saveWrongExecQuestions();
    for (final q in bookmarked) {
      if (!_bookmarkedExecQuestions.contains(q)) _bookmarkedExecQuestions.add(q);
    }
    _saveBookmarkedExecQuestions();
    messenger.showSnackBar(SnackBar(
      content: Text('実行練習（復習）: 正解 $correct / $total'),
      duration: const Duration(seconds: 4),
    ));
  }

  void _navigateToBookmarkedExecQuiz() async {
    if (_bookmarkedExecQuestions.isEmpty) return;
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final snapshot = List<ExecQuestion>.from(_bookmarkedExecQuestions)..shuffle();
    final result = await nav.push<(List<ExecQuestion>, int, int, List<ExecQuestion>, List<ExecQuestion>)?>(
      MaterialPageRoute(
        builder: (_) => ExecutionPracticePage(questions: snapshot),
      ),
    );
    if (!mounted || result == null) return;
    setState(() { _blockPointerEvents = true; });
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;
    final (_, correct, total, bookmarked, ignored) = result;
    _checkDayReset();
    setState(() {
      _blockPointerEvents = false;
      _progress = _progress.addSession(correct, total);
      _dailyAnswered += total;
    });
    for (final q in bookmarked) {
      if (!_bookmarkedExecQuestions.contains(q)) _bookmarkedExecQuestions.add(q);
    }
    _saveBookmarkedExecQuestions();
    messenger.showSnackBar(SnackBar(
      content: Text('あとで見直す練習: 正解 $correct / $total'),
      duration: const Duration(seconds: 4),
    ));
  }

  void _navigateToExecPracticeFiltered(String difficulty) async {
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final filtered = kExecQuestions.where((q) => q.difficulty == difficulty).toList();
    final result = await nav.push<(List<ExecQuestion>, int, int, List<ExecQuestion>, List<ExecQuestion>)?>(
      MaterialPageRoute(builder: (_) => ExecutionPracticePage(questions: filtered)),
    );
    if (!mounted || result == null) return;
    setState(() { _blockPointerEvents = true; });
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;
    final (wrongs, correct, total, bookmarked, _) = result;
    _checkDayReset();
    setState(() {
      _blockPointerEvents = false;
      _progress = _progress.addSession(correct, total);
      _dailyAnswered += total;
      for (final q in wrongs) {
        if (!_wrongExecQuestions.contains(q)) _wrongExecQuestions.add(q);
      }
    });
    _saveWrongExecQuestions();
    for (final q in bookmarked) {
      if (!_bookmarkedExecQuestions.contains(q)) _bookmarkedExecQuestions.add(q);
    }
    _saveBookmarkedExecQuestions();
    messenger.showSnackBar(SnackBar(
      content: Text('$difficulty 実行練習: 正解 $correct / $total'),
      duration: const Duration(seconds: 4),
    ));
  }

  Widget _buildHomeTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _HeroBanner(dailyAnswered: _dailyAnswered, dailyGoal: _dailyGoal),
          const SizedBox(height: 16),
          _ProgressCard(progress: _progress),
          const SizedBox(height: 16),
          _FeatureCardsSection(
            onExecBeginner: () => _navigateToExecPracticeFiltered('初級'),
            onExecIntermediate: () => _navigateToExecPracticeFiltered('中級'),
            onExecAdvanced: () => _navigateToExecPracticeFiltered('上級'),
            onWrongExecTap: _navigateToWrongExecQuiz,
            wrongExecCount: _wrongExecQuestions.length,
            onBookmarkedExecTap: _navigateToBookmarkedExecQuiz,
            bookmarkedExecCount: _bookmarkedExecQuestions.length,
          ),
        ],
      ),
    );
  }

}

// ============================================================
// Settings Page
// ============================================================

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          '設定',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E)),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            '広告',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF6B7280)),
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<bool>(
            valueListenable: adsRemovedNotifier,
            builder: (context, adsRemoved, _) {
              if (adsRemoved) {
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.green, size: 20),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          '広告非表示プランをご利用中です',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E)),
                        ),
                      ),
                    ],
                  ),
                );
              }
              return const _RemoveAdsBanner();
            },
          ),
          const SizedBox(height: 24),
          const Text(
            '規約・ポリシー',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF6B7280)),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                _SettingsLinkTile(
                  label: '利用規約',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const TermsOfServicePage()),
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFE5E7EB)),
                _SettingsLinkTile(
                  label: 'プライバシーポリシー',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const PrivacyPolicyPage()),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsLinkTile extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _SettingsLinkTile({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label, style: const TextStyle(fontSize: 14, color: Color(0xFF1A1A2E))),
      trailing: const Icon(Icons.chevron_right, size: 20, color: Color(0xFF9CA3AF)),
      onTap: onTap,
    );
  }
}

// ============================================================
// Remove Ads Banner
// ============================================================

class _RemoveAdsBanner extends StatefulWidget {
  const _RemoveAdsBanner();

  @override
  State<_RemoveAdsBanner> createState() => _RemoveAdsBannerState();
}

class _RemoveAdsBannerState extends State<_RemoveAdsBanner> {
  bool _busy = false;

  Future<void> _buy() async {
    final product = PurchaseManager.removeAdsProduct;
    if (product == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('現在購入できません。しばらくしてから再度お試しください。')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await PurchaseManager.buySubscription();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    setState(() => _busy = true);
    try {
      await PurchaseManager.restorePurchases();
      if (mounted && !adsRemovedNotifier.value) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('購入履歴が見つかりませんでした。')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final price = PurchaseManager.removeAdsProduct?.price;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1B2333),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.block, color: Colors.white, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '広告を非表示にする',
                  style: TextStyle(
                    color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  price != null ? '$price / 月' : '広告なしで快適に学習できます',
                  style: const TextStyle(color: Color(0xFFB0B8D0), fontSize: 11),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _busy ? null : _restore,
            child: const Text('復元', style: TextStyle(color: Color(0xFFB0B8D0), fontSize: 12)),
          ),
          ElevatedButton(
            onPressed: _busy ? null : _buy,
            style: ElevatedButton.styleFrom(
              backgroundColor: _kPrimary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: _busy
                ? const SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('登録する', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// Hero Banner
// ============================================================

class _HeroBanner extends StatelessWidget {
  final int dailyAnswered;
  final int dailyGoal;

  const _HeroBanner({required this.dailyAnswered, required this.dailyGoal});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0A1644), Color(0xFF1A3580)],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Color(0xFF4ADE80),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    const Text(
                      'Pythonプログラミング',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'プログラミングで\n得点力を伸ばそう！',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        height: 1.3,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      '処理の流れを追って理解を深めよう',
                      style: TextStyle(
                        color: Color(0xFFB0C4FF),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}


// ============================================================
// Progress Card
// ============================================================

class _ProgressCard extends StatelessWidget {
  final ProgressData progress;

  const _ProgressCard({required this.progress});

  @override
  Widget build(BuildContext context) {
    final pct = (progress.accuracy * 100).round();
    final mins = progress.studyMinutes;
    final hours = mins ~/ 60;
    final remMins = mins % 60;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '学習の進捗',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A1A2E),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _CircularGauge(
                value: progress.accuracy,
                label: '総合正答率',
                percent: progress.answeredCount == 0 ? '--%' : '$pct%',
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('正解した問題数',
                        style: TextStyle(fontSize: 11, color: Colors.grey)),
                    const SizedBox(height: 2),
                    RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: '${progress.correctCount}',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A1A2E),
                            ),
                          ),
                          TextSpan(
                            text: ' / ${progress.answeredCount}問',
                            style: const TextStyle(
                                fontSize: 13, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text('学習時間（概算）',
                        style: TextStyle(fontSize: 11, color: Colors.grey)),
                    const SizedBox(height: 2),
                    RichText(
                      text: TextSpan(
                        children: hours > 0
                            ? [
                                TextSpan(
                                  text: '$hours',
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1A1A2E),
                                  ),
                                ),
                                const TextSpan(
                                  text: '時間',
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.grey),
                                ),
                                TextSpan(
                                  text: ' $remMins',
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1A1A2E),
                                  ),
                                ),
                                const TextSpan(
                                  text: '分',
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.grey),
                                ),
                              ]
                            : [
                                TextSpan(
                                  text: '$remMins',
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1A1A2E),
                                  ),
                                ),
                                const TextSpan(
                                  text: '分',
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.grey),
                                ),
                              ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CircularGauge extends StatelessWidget {
  final double value;
  final String label;
  final String percent;

  const _CircularGauge({
    required this.value,
    required this.label,
    required this.percent,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 88,
      height: 88,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CircularProgressIndicator(
            value: value,
            strokeWidth: 8,
            strokeCap: StrokeCap.round,
            backgroundColor: const Color(0xFFEEF0FF),
            valueColor: const AlwaysStoppedAnimation<Color>(_kPrimary),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 8,
                    color: Colors.grey,
                    height: 1.2,
                  ),
                  textAlign: TextAlign.center,
                ),
                Text(
                  percent,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _kPrimary,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


// ============================================================
// Feature Cards Section
// ============================================================

class _FeatureCardsSection extends StatelessWidget {
  final VoidCallback onExecBeginner;
  final VoidCallback onExecIntermediate;
  final VoidCallback onExecAdvanced;
  final VoidCallback onWrongExecTap;
  final int wrongExecCount;
  final VoidCallback onBookmarkedExecTap;
  final int bookmarkedExecCount;

  const _FeatureCardsSection({
    required this.onExecBeginner,
    required this.onExecIntermediate,
    required this.onExecAdvanced,
    required this.onWrongExecTap,
    required this.wrongExecCount,
    required this.onBookmarkedExecTap,
    required this.bookmarkedExecCount,
  });

  @override
  Widget build(BuildContext context) {
    final beginnerCount = kExecQuestions.where((q) => q.difficulty == '初級').length;
    final intermediateCount = kExecQuestions.where((q) => q.difficulty == '中級').length;
    final advancedCount = kExecQuestions.where((q) => q.difficulty == '上級').length;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _DifficultyCard(
                label: '初級',
                count: beginnerCount,
                color: const Color(0xFF22C55E),
                bgColor: const Color(0xFFE8FBF0),
                onTap: onExecBeginner,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _DifficultyCard(
                label: '中級',
                count: intermediateCount,
                color: const Color(0xFF3B82F6),
                bgColor: const Color(0xFFEFF6FF),
                onTap: onExecIntermediate,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _DifficultyCard(
                label: '上級',
                count: advancedCount,
                color: const Color(0xFFEF4444),
                bgColor: const Color(0xFFFEF2F2),
                onTap: onExecAdvanced,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _WrongExecQuizCard(count: wrongExecCount, onTap: onWrongExecTap),
        const SizedBox(height: 10),
        _BookmarkedExecCard(count: bookmarkedExecCount, onTap: onBookmarkedExecTap),
      ],
    );
  }
}

class _DifficultyCard extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final Color bgColor;
  final VoidCallback onTap;

  const _DifficultyCard({
    required this.label,
    required this.count,
    required this.color,
    required this.bgColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$count問',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                '始める',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Color buttonColor;
  final VoidCallback onTap;

  const _FeatureCard({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.buttonColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A1A2E),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 10, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: onTap,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: buttonColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                '始める →',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// Wrong Exec Quiz Card
// ============================================================

class _WrongExecQuizCard extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _WrongExecQuizCard({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final has = count > 0;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: has ? const Color(0xFFFFF7ED) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: has
                ? const Color(0xFFF97316).withValues(alpha: 0.35)
                : const Color(0xFFE5E7EB),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: has
                    ? const Color(0xFFF97316).withValues(alpha: 0.15)
                    : const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.terminal,
                color: has ? const Color(0xFFF97316) : Colors.grey,
                size: 24,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '間違えた問題',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: has ? const Color(0xFF1A1A2E) : Colors.grey,
                    ),
                  ),
                ),
                if (has)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF97316),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$count件',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              has ? '苦手を克服しよう' : 'まだありません',
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: has ? const Color(0xFFF97316) : const Color(0xFFE5E7EB),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                has ? '始める →' : 'ロック中',
                style: TextStyle(
                  color: has ? Colors.white : Colors.grey,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// Bookmarked Exec Card
// ============================================================

class _BookmarkedExecCard extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _BookmarkedExecCard({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final has = count > 0;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: has ? const Color(0xFFFFFBEB) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: has
                ? const Color(0xFFF59E0B).withValues(alpha: 0.4)
                : const Color(0xFFE5E7EB),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: has
                    ? const Color(0xFFF59E0B).withValues(alpha: 0.15)
                    : const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.bookmark,
                color: has ? const Color(0xFFF59E0B) : Colors.grey,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'あとで見直す',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: has ? const Color(0xFF1A1A2E) : Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    has ? '$count件の問題を保存中' : 'まだブックマークがありません',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
            if (has)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '確認する →',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// Topic Card (for Study tab)
// ============================================================

// ============================================================
// Execution Practice Page
// ============================================================

List<InlineSpan> _pythonHighlight(String code) {
  const defaultStyle = TextStyle(color: Color(0xFFCDD9E5));
  const keywordStyle = TextStyle(color: Color(0xFFFF7B72));
  const builtinStyle = TextStyle(color: Color(0xFFD2A8FF));
  const numberStyle = TextStyle(color: Color(0xFF79C0FF));
  const stringStyle = TextStyle(color: Color(0xFF96D0FF));
  const commentStyle = TextStyle(color: Color(0xFF8B949E));

  final spans = <InlineSpan>[];
  // match comments, double-quoted strings, keywords, builtins, numbers
  final tokenRe = RegExp(
    r'(#[^\n]*)'
    r'|("(?:[^"\\]|\\.)*")'
    r'|\b(def|for|if|elif|else|return|in|and|or|not|True|False|None|while|class|import|from|as|pass|break|continue)\b'
    r'|\b(print|range|len|input|int|str|float|list|dict|tuple|set|append|extend|type|sum|max|min|abs)\b'
    r'|\b(\d+\.?\d*)\b',
  );

  int pos = 0;
  for (final m in tokenRe.allMatches(code)) {
    if (m.start > pos) {
      spans.add(TextSpan(text: code.substring(pos, m.start), style: defaultStyle));
    }
    TextStyle style;
    if (m.group(1) != null) {
      style = commentStyle;
    } else if (m.group(2) != null) {
      style = stringStyle;
    } else if (m.group(3) != null) {
      style = keywordStyle;
    } else if (m.group(4) != null) {
      style = builtinStyle;
    } else {
      style = numberStyle;
    }
    spans.add(TextSpan(text: m.group(0)!, style: style));
    pos = m.end;
  }
  if (pos < code.length) {
    spans.add(TextSpan(text: code.substring(pos), style: defaultStyle));
  }
  return spans;
}

class ExecutionPracticePage extends StatefulWidget {
  final List<ExecQuestion>? questions;
  const ExecutionPracticePage({super.key, this.questions});

  @override
  State<ExecutionPracticePage> createState() => _ExecutionPracticePageState();
}

class _ExecutionPracticePageState extends State<ExecutionPracticePage> {
  late final List<ExecQuestion> _questions;
  final List<ExecQuestion> _wrongQuestions = [];
  final List<ExecQuestion> _correctlyAnswered = [];
  int _currentIndex = 0;
  int? _selectedChoice;
  bool _executed = false;
  bool _showHint = false;
  int _correctCount = 0;
  int _answeredCount = 0;
  int _streak = 0;
  int _studySeconds = 0;
  late final Timer _timer;
  final Set<int> _bookmarked = {};
  final _scrollController = ScrollController();
  final _resultKey = GlobalKey();

  static const _adFrequency = 5; // 何問ごとにインタースティシャル広告を表示するか
  static const _maxAdLoadRetries = 3;
  InterstitialAd? _interstitialAd;
  int _execCountSinceAd = 0;
  int _adLoadRetryCount = 0;

  @override
  void initState() {
    super.initState();
    if (_adsSupported) {
      // 広告SDKの初期化(ATT許諾を含む)が終わるまで待ってからロードする。
      // 初期化前にロードすると失敗しやすいため。
      _ensureAdsInitialized().then((_) {
        if (mounted && _adsSupported) _loadInterstitialAd();
      });
    }
    _questions = widget.questions != null
        ? (List<ExecQuestion>.from(widget.questions!)..shuffle())
        : (List<ExecQuestion>.from(kExecQuestions)..shuffle()).take(10).toList();
    _timer = Timer.periodic(const Duration(seconds: 1), _onTick);
  }

  void _onTick(Timer _) {
    if (!mounted) return;
    setState(() {
      _studySeconds++;
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    _scrollController.dispose();
    _interstitialAd?.dispose();
    super.dispose();
  }

  void _loadInterstitialAd() {
    InterstitialAd.load(
      adUnitId: _interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _adLoadRetryCount = 0;
          _interstitialAd = ad;
        },
        onAdFailedToLoad: (error) {
          _interstitialAd = null;
          // 新規に作成した広告ユニットは反映まで時間がかかることがあるため、
          // 少し待って数回まで再試行する。
          if (_adLoadRetryCount < _maxAdLoadRetries) {
            _adLoadRetryCount++;
            Future.delayed(const Duration(seconds: 20), () {
              if (mounted && _adsSupported) _loadInterstitialAd();
            });
          }
        },
      ),
    );
  }

  void _showInterstitialAdThenAdvance() {
    final ad = _interstitialAd;
    if (ad == null) {
      _advanceToNextQuestion();
      return;
    }
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _interstitialAd = null;
        _loadInterstitialAd();
        _advanceToNextQuestion();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _interstitialAd = null;
        _loadInterstitialAd();
        _advanceToNextQuestion();
      },
    );
    _execCountSinceAd = 0;
    ad.show();
  }

  ExecQuestion get _current => _questions[_currentIndex];
  bool get _isCorrect => _selectedChoice == _current.correctIndex;

  void _selectChoice(int index) {
    if (_executed) return;
    setState(() => _selectedChoice = index);
  }

  void _execute() {
    if (_selectedChoice == null) return;
    setState(() {
      _executed = true;
      _answeredCount++;
      _execCountSinceAd++;
      if (_isCorrect) {
        _correctCount++;
        _streak++;
        if (!_correctlyAnswered.contains(_current)) _correctlyAnswered.add(_current);
      } else {
        _streak = 0;
        if (!_wrongQuestions.contains(_current)) {
          _wrongQuestions.add(_current);
        }
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final resultContext = _resultKey.currentContext;
      if (resultContext != null) {
        Scrollable.ensureVisible(
          resultContext,
          alignment: 0.0,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _goNext() {
    if (_currentIndex >= _questions.length - 1) return;
    if (_adsSupported && _execCountSinceAd >= _adFrequency) {
      _showInterstitialAdThenAdvance();
    } else {
      _advanceToNextQuestion();
    }
  }

  void _advanceToNextQuestion() {
    if (!mounted || _currentIndex >= _questions.length - 1) return;
    setState(() {
      _currentIndex++;
      _selectedChoice = null;
      _executed = false;
      _showHint = false;
    });
    _scrollController.jumpTo(0);
  }

  void _goPrev() {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
        _selectedChoice = null;
        _executed = false;
        _showHint = false;
      });
      _scrollController.jumpTo(0);
    }
  }

  void _toggleBookmark() {
    setState(() {
      if (_bookmarked.contains(_currentIndex)) {
        _bookmarked.remove(_currentIndex);
      } else {
        _bookmarked.add(_currentIndex);
      }
    });
  }

  String _formatStudy() {
    if (_studySeconds < 60) return '$_studySeconds秒';
    final h = _studySeconds ~/ 3600;
    final m = (_studySeconds % 3600) ~/ 60;
    return h == 0 ? '$m分' : '$h時間$m分';
  }

  void _exitPage() {
    _timer.cancel();
    final bookmarked = _bookmarked.map((i) => _questions[i]).toList();
    Navigator.of(context).pop(
      _answeredCount > 0 || bookmarked.isNotEmpty
          ? (_wrongQuestions, _correctCount, _answeredCount, bookmarked, _correctlyAnswered)
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 18),
            onPressed: _exitPage,
        ),
        title: const Text(
          '問題演習',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(
              _bookmarked.contains(_currentIndex)
                  ? Icons.bookmark
                  : Icons.bookmark_outline,
              size: 22,
              color: _bookmarked.contains(_currentIndex) ? _kPrimary : null,
            ),
            onPressed: _toggleBookmark,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildProgressHeader(),
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildQuestion(),
                  if (_executed) ...[
                    const SizedBox(height: 20),
                    KeyedSubtree(
                      key: _resultKey,
                      child: const Divider(color: Color(0xFFE5E7EB)),
                    ),
                    const SizedBox(height: 12),
                    _buildResult(),
                  ],
                ],
              ),
            ),
          ),
          _buildNavBar(),
          _buildStatsBar(),
        ],
      ),
    );
  }

  Widget _buildProgressHeader() {
    final progress = (_currentIndex + 1) / _questions.length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Row(
        children: [
          Text('問題 ', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          Text(
            '${_currentIndex + 1}',
            style: const TextStyle(
              fontSize: 16, fontWeight: FontWeight.bold, color: _kPrimary,
            ),
          ),
          Text(' / ${_questions.length}',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          const SizedBox(width: 10),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: const Color(0xFFE5E7EB),
                valueColor: const AlwaysStoppedAnimation(_kPrimary),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _exitPage,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                '終了する',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestion() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          children: _current.tags.map((tag) {
            final isFirst = tag == _current.tags.first;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isFirst ? _kPrimary : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
                border: isFirst ? null : Border.all(color: const Color(0xFFCCCCCC)),
              ),
              child: Text(
                tag,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: isFirst ? Colors.white : Colors.grey.shade600,
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        Text(
          _current.questionText,
          style: const TextStyle(
            fontSize: 14, height: 1.6, color: Color(0xFF1A1A2E),
          ),
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () => setState(() => _showHint = !_showHint),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _showHint ? const Color(0xFFFFFBEB) : const Color(0xFFFFF9F0),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _showHint ? const Color(0xFFFDE68A) : const Color(0xFFFFD88A),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.lightbulb_outline, size: 14, color: Color(0xFFD97706)),
                    const SizedBox(width: 6),
                    const Text(
                      'ヒント（関数・メソッドの確認）',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFD97706),
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      _showHint ? Icons.expand_less : Icons.expand_more,
                      size: 16,
                      color: const Color(0xFFD97706),
                    ),
                  ],
                ),
                if (_showHint) ...[
                  const SizedBox(height: 8),
                  const Divider(height: 1, color: Color(0xFFFDE68A)),
                  const SizedBox(height: 8),
                  Text(
                    _current.noteText,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF78350F),
                      height: 1.8,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _ExecCodeBlock(code: _current.code, language: _current.language),
        const SizedBox(height: 16),
        Text(
          '選択肢を選んでください',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
        ),
        const SizedBox(height: 8),
        ...List.generate(_current.choices.length, (i) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _ExecChoiceRadio(
            label: _current.choices[i],
            selected: _selectedChoice == i,
            onTap: () => _selectChoice(i),
          ),
        )),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _selectedChoice != null && !_executed ? _execute : null,
            icon: const Icon(Icons.play_arrow, size: 18),
            label: const Text(
              '結果を確認',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kPrimary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFFD0D5E8),
              disabledForegroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResult() {
    final correct = _isCorrect;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              '実行結果',
              style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E),
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: correct
                    ? const Color(0xFFE8F5E9)
                    : const Color(0xFFFFEBEE),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    correct ? Icons.check_circle : Icons.cancel,
                    size: 14,
                    color: correct ? Colors.green : Colors.red,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    correct ? '正解！' : '不正解',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: correct ? Colors.green : Colors.red,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text('実行したコード',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1B2333),
            borderRadius: BorderRadius.circular(8),
          ),
          child: RichText(
            text: TextSpan(
              children: _pythonHighlight(_current.code),
              style: const TextStyle(
                fontFamily: 'monospace', fontSize: 12, height: 1.6,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text('出力結果',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1B2333),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '> ${_current.output}',
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              color: Color(0xFFE2E8F0),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: correct ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                correct ? Icons.check_circle : Icons.cancel,
                color: correct ? Colors.green : Colors.red,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      correct ? '正解です！' : '不正解です',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: correct
                            ? Colors.green.shade700
                            : Colors.red.shade700,
                      ),
                    ),
                    Text(
                      '正しい出力結果は「${_current.output}」です。',
                      style: TextStyle(
                        fontSize: 12,
                        color: correct
                            ? Colors.green.shade700
                            : Colors.red.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: const Color(0xFFEEF0FF),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(
                Icons.menu_book_outlined,
                size: 14,
                color: _kPrimary,
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              '解説',
              style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F7FF),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFDDE3FF)),
          ),
          child: Text(
            _current.aiExplanation,
            style: const TextStyle(
              fontSize: 13.5,
              color: Color(0xFF1A1A2E),
              height: 1.8,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: const Color(0xFFEEF0FF),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(
                Icons.account_tree_outlined,
                size: 14,
                color: _kPrimary,
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              '処理の流れ',
              style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E2E),
            borderRadius: BorderRadius.circular(10),
          ),
          child: SelectableText(
            _current.calculationStep,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              color: Color(0xFFCDD6F4),
              height: 1.9,
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildNavBar() {
    final isBookmarked = _bookmarked.contains(_currentIndex);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Row(
        children: [
          OutlinedButton.icon(
            onPressed: _currentIndex > 0 ? _goPrev : null,
            icon: const Icon(Icons.arrow_back, size: 14),
            label: const Text('前の問題', style: TextStyle(fontSize: 12)),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              side: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: _toggleBookmark,
            icon: Icon(
              isBookmarked ? Icons.bookmark : Icons.bookmark_outline,
              size: 14,
              color: isBookmarked ? _kPrimary : Colors.grey,
            ),
            label: Text(
              'あとで見直す',
              style: TextStyle(
                fontSize: 12,
                color: isBookmarked ? _kPrimary : Colors.grey,
              ),
            ),
          ),
          const Spacer(),
          if (_currentIndex < _questions.length - 1)
            ElevatedButton.icon(
              onPressed: _goNext,
              icon: const Icon(Icons.arrow_forward, size: 14),
              label: const Text('次の問題', style: TextStyle(fontSize: 12)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
            )
          else if (_executed)
            ElevatedButton.icon(
              onPressed: _exitPage,
              icon: const Icon(Icons.check, size: 14),
              label: const Text('完了する', style: TextStyle(fontSize: 12)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF97316),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
            )
          else
            ElevatedButton.icon(
              onPressed: null,
              icon: const Icon(Icons.arrow_forward, size: 14),
              label: const Text('次の問題', style: TextStyle(fontSize: 12)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatsBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: const Color(0xFFF8F9FB),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🔥', style: TextStyle(fontSize: 13)),
          const SizedBox(width: 3),
          Text(
            '連続正解 $_streak問',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
          ),
          const SizedBox(width: 12),
          const Icon(Icons.timer_outlined, size: 13, color: Colors.grey),
          const SizedBox(width: 3),
          Text(
            _formatStudy(),
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

class _ExecCodeBlock extends StatelessWidget {
  final String code;
  final String language;

  const _ExecCodeBlock({required this.code, required this.language});

  @override
  Widget build(BuildContext context) {
    final lines = code.split('\n');
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1B2333),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2D3F5A),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    language,
                    style: const TextStyle(
                      color: Color(0xFF8EA3BF),
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: code));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('コードをコピーしました'),
                      duration: Duration(seconds: 1),
                      behavior: SnackBarBehavior.floating,
                    ));
                  },
                  child: Icon(Icons.copy_outlined, size: 15, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: List.generate(
                    lines.length,
                    (i) => Text(
                      '${i + 1}',
                      style: const TextStyle(
                        color: Color(0xFF4B5E78),
                        fontSize: 12.5,
                        fontFamily: 'monospace',
                        height: 1.6,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      children: _pythonHighlight(code),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12.5,
                        height: 1.6,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ExecChoiceRadio extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ExecChoiceRadio({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFF0F4FF) : Colors.white,
          border: Border.all(
            color: selected ? _kPrimary : const Color(0xFFE5E7EB),
            width: selected ? 1.5 : 1.0,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? _kPrimary : const Color(0xFFCCCCCC),
                  width: 2,
                ),
                color: selected ? _kPrimary : Colors.transparent,
              ),
              child: selected
                  ? const Center(
                      child: Icon(Icons.circle, size: 7, color: Colors.white),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  color: selected ? _kPrimary : const Color(0xFF1A1A2E),
                  fontWeight:
                      selected ? FontWeight.w500 : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

