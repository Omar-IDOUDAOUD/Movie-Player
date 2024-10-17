import 'package:flutter/material.dart';
import 'package:movie_player/routes/landing.dart';

void main() {
  print('yakhhh');
  runApp(const MoviePlayer());
}


class MoviePlayer extends StatelessWidget {
  const MoviePlayer({super.key});

  @override
  Widget build(BuildContext context) {
    print('tfooo');
    return const MaterialApp(
      home: LandingPage(),
    );
  }
}
