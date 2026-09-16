import 'package:flutter/material.dart';

import 'theme/app_theme.dart';
import 'ui/home_page.dart';

class PicToolApp extends StatelessWidget {
  const PicToolApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '图片处理工具',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const HomePage(),
    );
  }
}
