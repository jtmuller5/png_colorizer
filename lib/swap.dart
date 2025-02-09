import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For loading assets
import 'package:image/image.dart' as imgLib;
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

void main() {
  runApp(MaterialApp(home: ImageColorSwapApp()));
}

class ImageColorSwapApp extends StatefulWidget {
  @override
  _ImageColorSwapAppState createState() => _ImageColorSwapAppState();
}

class _ImageColorSwapAppState extends State<ImageColorSwapApp> {
  imgLib.Image? originalImage;
  Uint8List? displayedImageBytes;
  // Mapping from an original pixel’s ARGB int to a replacement color’s ARGB int.
  Map<int, int> colorMappings = {};

  // GlobalKey attached to the Image widget.
  final GlobalKey _imageKey = GlobalKey();

  // Tolerance for matching colors (Euclidean distance in RGB space).
  // Adjust this value as needed.
  // 0-5 is very low
  // 5-10 is low
  // 10-20 is medium
  // 20-40 is high
  final double tolerance = 65.0;

  @override
  void initState() {
    super.initState();
    loadAssetImage();
  }

  /// Loads an image from assets and decodes it.
  Future<void> loadAssetImage() async {
    ByteData imageData = await rootBundle.load('assets/sample.png');
    Uint8List bytes = imageData.buffer.asUint8List();
    originalImage = imgLib.decodeImage(bytes);

    if (originalImage != null) {
      // Ensure we have an RGBA image.
      originalImage = originalImage!.convert(numChannels: 4, alpha: 255);
      setState(() {
        displayedImageBytes =
            Uint8List.fromList(imgLib.encodePng(originalImage!));
      });
    }
  }

  /// Updated helper that converts a Pixel to an ARGB int.
  int pixelToInt(imgLib.Pixel pixel) {
    // The image package stores colors in RGBA order.
    return (pixel.a.toInt() << 24) |
        (pixel.r.toInt() << 16) |
        (pixel.g.toInt() << 8) |
        (pixel.b.toInt());
  }

  /// Converts a Flutter Color to an ARGB int.
  int colorToInt(Color color) {
    return color.value; // Flutter Color.value is in 0xAARRGGBB format.
  }

  /// Compute the Euclidean distance between a pixel's color and a target color (ignoring alpha).
  double colorDistance(imgLib.Pixel pixel, int targetColor) {
    final int r1 = pixel.r.toInt();
    final int g1 = pixel.g.toInt();
    final int b1 = pixel.b.toInt();

    final int r2 = (targetColor >> 16) & 0xFF;
    final int g2 = (targetColor >> 8) & 0xFF;
    final int b2 = targetColor & 0xFF;

    return math.sqrt(
        math.pow(r1 - r2, 2) + math.pow(g1 - g2, 2) + math.pow(b1 - b2, 2));
  }

  /// Applies the color mappings over the entire image using a tolerance-based match.
  void updateImage() {
    if (originalImage == null) return;
    // Clone the original image so we don’t modify it permanently.
    final modifiedImage = originalImage!.clone();

    // Iterate over every pixel.
    for (final pixel in modifiedImage) {
      // For each mapping entry (originalColor -> newColor)
      for (final mapping in colorMappings.entries) {
        // If the color distance is less than our tolerance, update the pixel.
        if (colorDistance(pixel, mapping.key) <= tolerance) {
          int newColor = mapping.value;
          pixel.r = (newColor >> 16) & 0xFF;
          pixel.g = (newColor >> 8) & 0xFF;
          pixel.b = newColor & 0xFF;
          pixel.a = (newColor >> 24) & 0xFF;
          break; // Stop checking further mappings once updated.
        }
      }
    }

    setState(() {
      displayedImageBytes = Uint8List.fromList(imgLib.encodePng(modifiedImage));
    });
  }

  /// Handles taps on the image.
  void onImageTap(BuildContext context, TapDownDetails details) async {
    if (originalImage == null || displayedImageBytes == null) return;

    // Use the GlobalKey to get the RenderBox of the Image widget.
    final RenderBox imageBox =
        _imageKey.currentContext!.findRenderObject() as RenderBox;
    // Get the top-left position of the image in global coordinates.
    final imagePosition = imageBox.localToGlobal(Offset.zero);
    // Compute the tap’s position relative to the image.
    final localPosition = details.globalPosition - imagePosition;
    final imageSize = imageBox.size;

    // Map the tap coordinate to the coordinate in the image.
    int imgX =
        (localPosition.dx * originalImage!.width / imageSize.width).toInt();
    int imgY =
        (localPosition.dy * originalImage!.height / imageSize.height).toInt();

    // Make sure the computed coordinates are within the image bounds.
    if (imgX < 0 ||
        imgX >= originalImage!.width ||
        imgY < 0 ||
        imgY >= originalImage!.height) {
      return;
    }

    // Use the updated API: getPixel returns a Pixel object.
    final pixel = originalImage!.getPixel(imgX, imgY);
    int origColorInt = pixelToInt(pixel);
    Color tappedColor = Color(origColorInt);

    // Show a color picker dialog.
    Color newColor = tappedColor;
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Pick Replacement Color'),
          content: SingleChildScrollView(
            child: ColorPicker(
              pickerColor: tappedColor,
              onColorChanged: (color) {
                newColor = color;
              },
              showLabel: true,
              pickerAreaHeightPercent: 0.8,
            ),
          ),
          actions: [
            TextButton(
              child: Text('Select'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );

    // Store the mapping from the tapped pixel’s color to the replacement color.
    colorMappings[origColorInt] = colorToInt(newColor);
    updateImage();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Flutter Color Swap')),
      body: Center(
        child: displayedImageBytes == null
            ? CircularProgressIndicator()
            : GestureDetector(
                onTapDown: (details) => onImageTap(context, details),
                child: Image.memory(
                  displayedImageBytes!,
                  key: _imageKey, // Attach the GlobalKey here.
                  fit: BoxFit.contain,
                ),
              ),
      ),
    );
  }
}
