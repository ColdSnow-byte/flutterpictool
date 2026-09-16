import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/rust/frb_generated.dart';
import 'src/ui/widgets/liquid_glass.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 初始化 rust 侧运行时，之后所有 Rust 能力都可以通过生成的绑定调用
  await RustLib.init();
  // 预加载液态玻璃着色器：不可用时组件会自动退回模糊实现
  //await LiquidGlassProgram.load();
  runApp(const PicToolApp());
}
