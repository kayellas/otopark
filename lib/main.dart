
import 'package:flutter/material.dart';
import 'package:otopark_app/screens/map_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'İzmir Otopark',
      theme: ThemeData(
        primaryColor: const Color(0xFF246AFB),
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF246AFB)),
        useMaterial3: true,
      ),
      home: const MapScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}