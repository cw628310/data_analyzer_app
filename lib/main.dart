import 'package:flutter/material.dart';

import 'pages/home_page.dart';

void main() {
  runApp(const DataAnalyzerApp());
}

class DataAnalyzerApp extends StatelessWidget {
  const DataAnalyzerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '数据分析仪',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2563EB)),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class MyApp extends DataAnalyzerApp {
  const MyApp({super.key});
}
