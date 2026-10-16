// 测试环境配置：在运行任何测试前初始化 sqflite 的 FFI 后端。
// 否则 App 在测试中打开数据库会抛 "databaseFactory not initialized"
//（默认 sqflite 全局 databaseFactory 仅在真机/模拟器的平台通道下初始化）。
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> testExecutable(Future<void> Function() testMain) async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  await testMain();
}
