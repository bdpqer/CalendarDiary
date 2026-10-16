import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'home/app_lock_gate.dart';
import 'home/homepage.dart';
import 'user_data/diary_database.dart';
import 'user_data/task_reminder.dart';
import 'theme/app_colors.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 事项闹钟提醒：初始化通知渠道，并在启动时重排未到期提醒
  TaskReminderService.instance.init();
  // 媒体孤儿文件清扫：删掉「未被任何日记引用且已存在超过 24 小时」的文件，
  // 兜底覆盖「录音/选图后未保存、随后进程被系统杀死」导致的残留。
  // 后台静默执行，失败不影响启动（详见 DiaryDatabase.purgeOrphanMedia）
  unawaited(DiaryDatabase.instance.purgeOrphanMedia());
  // 系统栏与 App 背景统一为白色：状态栏透明 + 深色图标，
  // 系统导航栏白色 + 深色图标（Android 15+ 强制 edge-to-edge 时，
  // 导航栏区域会透出 App 自身背景，底部 Tab 栏为白色即保持一致）
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.white,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.dark,
    systemNavigationBarContrastEnforced: false,
  ));
  runApp(const WannianDiaryApp());
}

class WannianDiaryApp extends StatelessWidget {
  const WannianDiaryApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 沿用原小枣日历配色基调：#C38D4B 描边 / #FCF6F1 底
    const seed = AppColors.primary;
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      primary: seed,
      secondary: AppColors.green,
      surface: AppColors.surfaceWarm,
    );

    return MaterialApp(
      title: '日历日记',
      debugShowCheckedModeBanner: false,
      // 中文本地化：日期/时间选择器等系统组件按钮与月份显示中文
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        colorScheme: scheme,
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: AppColors.textStrong,
          elevation: 0,
          centerTitle: true,
        ),
        bottomSheetTheme: const BottomSheetThemeData(backgroundColor: Colors.transparent),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: seed,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ),
      home: const AppLockGate(child: HomePage()),
    );
  }
}
