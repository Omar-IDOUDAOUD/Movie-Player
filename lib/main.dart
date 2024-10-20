import 'package:flutter/material.dart';
import 'package:movie_player/routes/landing.dart';

void main() {
  runApp(const MoviePlayer());
}


class MoviePlayer extends StatelessWidget {
  const MoviePlayer({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: LandingPage(),
    );
  }
}
