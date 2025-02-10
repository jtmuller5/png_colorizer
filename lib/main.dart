import 'package:flutter/material.dart';
import 'package:png_colorizer/tools/png_colorizer.dart';
import 'package:png_colorizer/tools/svg_colorizer.dart';

void main() {
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ImageColorSwapApp(),
    ),
  );
}

class ImageColorSwapApp extends StatefulWidget {
  @override
  _ImageColorSwapAppState createState() => _ImageColorSwapAppState();
}

class _ImageColorSwapAppState extends State<ImageColorSwapApp> {
  String mode = 'svg'; // 'png' or 'svg'

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        body: Column(
      children: [
        SwitchListTile(
          value: mode == 'png',
          onChanged: (value) {
            setState(() {
              mode = value ? 'png' : 'svg';
            });
          },
          title: Text('Mode: ${mode.toUpperCase()}'),
        ),
        Expanded(
          child: mode == 'png' ? PngColorizer() : SvgColorizer(),
        ),
      ],
    ));
  }
}
