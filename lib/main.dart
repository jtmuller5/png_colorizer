import 'dart:collection';
import 'dart:math';
import 'dart:typed_data';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For loading assets
import 'package:image/image.dart' as imgLib;
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:html' as html; // For web only, consider using conditional imports

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

  // GlobalKey attached to the Image widget to get its RenderBox.
  final GlobalKey _imageKey = GlobalKey();

  // Tolerance for matching colors (using Euclidean distance in RGB space).
  double tolerance = 65.0;

  // List of recently used colors.
  List<Color> recentColors = [];

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
      // Ensure the image has 4 channels (RGBA).
      originalImage = originalImage!.convert(numChannels: 4, alpha: 255);
      setState(() {
        displayedImageBytes =
            Uint8List.fromList(imgLib.encodePng(originalImage!));
      });
    }
  }

  /// Converts a Pixel (from the image package) to a 32-bit ARGB int.
  int pixelToInt(imgLib.Pixel pixel) {
    // The image package stores colors in RGBA order.
    return (pixel.a.toInt() << 24) |
        (pixel.r.toInt() << 16) |
        (pixel.g.toInt() << 8) |
        (pixel.b.toInt());
  }

  /// Converts a Flutter Color to a 32-bit ARGB int.
  int colorToInt(Color color) {
    return color.value;
  }

  /// Computes the Euclidean distance between a pixel’s color and a target color (ignoring alpha).
  double colorDistance(imgLib.Pixel pixel, int targetColor) {
    final int r1 = pixel.r.toInt();
    final int g1 = pixel.g.toInt();
    final int b1 = pixel.b.toInt();

    final int r2 = (targetColor >> 16) & 0xFF;
    final int g2 = (targetColor >> 8) & 0xFF;
    final int b2 = targetColor & 0xFF;

    return sqrt(pow(r1 - r2, 2) + pow(g1 - g2, 2) + pow(b1 - b2, 2));
  }

  /// Posterizes the image by reducing each channel to a specified number of levels.
  /// This can help reduce the smooth color transitions caused by antialiasing.
  void posterizeImage(imgLib.Image image, int levels) {
    double step = 255 / (levels - 1);
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        pixel.r = (pixel.r / step).round() * step.toInt();
        pixel.g = (pixel.g / step).round() * step.toInt();
        pixel.b = (pixel.b / step).round() * step.toInt();
        // Alpha remains unchanged.
      }
    }
  }

  /// Flood fill algorithm: returns a set of Points (x,y) representing the connected region.
  Set<Point<int>> floodFillRegion(imgLib.Image image, int startX, int startY,
      int targetColor, double tolerance) {
    final Set<Point<int>> region = {};
    final Queue<Point<int>> queue = Queue<Point<int>>();
    final Point<int> startPoint = Point(startX, startY);
    queue.add(startPoint);
    region.add(startPoint);

    while (queue.isNotEmpty) {
      final Point<int> p = queue.removeFirst();

      // 4-connected neighbors (left, right, up, down).
      for (final neighbor in [
        Point(p.x - 1, p.y),
        Point(p.x + 1, p.y),
        Point(p.x, p.y - 1),
        Point(p.x, p.y + 1),
      ]) {
        // Skip if out of bounds.
        if (neighbor.x < 0 ||
            neighbor.y < 0 ||
            neighbor.x >= image.width ||
            neighbor.y >= image.height) {
          continue;
        }
        if (region.contains(neighbor)) continue;

        final imgLib.Pixel neighborPixel =
            image.getPixel(neighbor.x, neighbor.y);
        if (colorDistance(neighborPixel, targetColor) <= tolerance) {
          region.add(neighbor);
          queue.add(neighbor);
        }
      }
    }
    return region;
  }

  /// Opens the color picker dialog. It shows both the ColorPicker and recent colors.
  Future<Color> openColorPickerDialog(Color tappedColor) async {
    Color selectedColor = tappedColor;

    await showDialog(
      context: context,
      builder: (context) {
        // Use StatefulBuilder to update dialog state.
        return StatefulBuilder(builder: (context, setStateDialog) {
          return AlertDialog(
            title: Text('Pick Replacement Color'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // The color picker.
                  ColorPicker(
                    pickerColor: selectedColor,
                    onColorChanged: (color) {
                      setStateDialog(() {
                        selectedColor = color;
                      });
                    },
                    showLabel: true,
                    pickerAreaHeightPercent: 0.8,
                  ),
                  SizedBox(height: 10),
                  // Recently used colors.
                  if (recentColors.isNotEmpty) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Recent Colors:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: recentColors.map((color) {
                        return GestureDetector(
                          onTap: () {
                            setStateDialog(() {
                              selectedColor = color;
                            });
                          },
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.black38),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ],
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
        });
      },
    );
    return selectedColor;
  }

  /// Handles taps on the image.
  void onImageTap(BuildContext context, TapDownDetails details) async {
    if (originalImage == null || displayedImageBytes == null) return;

    // Obtain the RenderBox for the displayed image.
    final RenderBox imageBox =
        _imageKey.currentContext!.findRenderObject() as RenderBox;
    final Offset imagePosition = imageBox.localToGlobal(Offset.zero);
    final Offset localPosition = details.globalPosition - imagePosition;
    final Size imageSize = imageBox.size;

    // Map the tap coordinate to the corresponding coordinate in the image.
    int imgX =
        (localPosition.dx * originalImage!.width / imageSize.width).toInt();
    int imgY =
        (localPosition.dy * originalImage!.height / imageSize.height).toInt();

    if (imgX < 0 ||
        imgX >= originalImage!.width ||
        imgY < 0 ||
        imgY >= originalImage!.height) {
      return;
    }

    // Create a posterized clone of the original image to reduce antialiasing effects.
    imgLib.Image processedImage = originalImage!.clone();
    posterizeImage(
        processedImage, 4); // Adjust levels (e.g., 4 or 8) as needed.

    // Use the posterized image for flood fill region detection.
    final imgLib.Pixel tappedPixel = processedImage.getPixel(imgX, imgY);
    int targetColorInt = pixelToInt(tappedPixel);
    Color tappedColor = Color(targetColorInt);

    // Open the color picker dialog.
    Color newColor = await openColorPickerDialog(tappedColor);

    // Add the selected color to the recent colors list (if not already present).
    if (!recentColors.contains(newColor)) {
      setState(() {
        recentColors.insert(0, newColor);
        if (recentColors.length > 5) {
          recentColors = recentColors.sublist(0, 5);
        }
      });
    }

    // Compute the flood filled region on the posterized image.
    final Set<Point<int>> region =
        floodFillRegion(processedImage, imgX, imgY, targetColorInt, tolerance);

    int newColorInt = colorToInt(newColor);

    // Update the corresponding pixels in the original image.
    for (final Point<int> p in region) {
      final imgLib.Pixel pixel = originalImage!.getPixel(p.x, p.y);
      pixel.r = (newColorInt >> 16) & 0xFF;
      pixel.g = (newColorInt >> 8) & 0xFF;
      pixel.b = newColorInt & 0xFF;
      pixel.a = (newColorInt >> 24) & 0xFF;
    }

    setState(() {
      displayedImageBytes =
          Uint8List.fromList(imgLib.encodePng(originalImage!));
    });
  }

  /// Applies a Gaussian blur to the current image and updates the display.
  void applyGaussianBlur() {
    if (originalImage == null) return;
    // Apply Gaussian blur with a radius of 2 (adjust as needed).
    originalImage = imgLib.gaussianBlur(originalImage!, radius: 1);
    setState(() {
      displayedImageBytes =
          Uint8List.fromList(imgLib.encodePng(originalImage!));
    });
  }

  /// Saves the current displayed image as a PNG file.

  Future<void> saveImage() async {
    if (originalImage == null) return;
    try {
      final imgLib.Image antialiasedImage = originalImage!.clone();
      final Uint8List antialiasedBytes =
          Uint8List.fromList(imgLib.encodePng(antialiasedImage));
      final String fileName =
          'image_${DateTime.now().millisecondsSinceEpoch}.png';
      if (kIsWeb) {
        final blob = html.Blob([antialiasedBytes], 'image/png');
        final url = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.AnchorElement(href: url)
          ..download = fileName
          ..style.display = 'none';
        html.document.body!.append(anchor);
        anchor.click();
        anchor.remove();
        html.Url.revokeObjectUrl(url);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download initiated as $fileName'),
          ),
        );
      } else {
        final Directory directory = await getApplicationDocumentsDirectory();
        final String filePath = '${directory.path}/$fileName';
        final File file = File(filePath);
        await file.writeAsBytes(antialiasedBytes);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Image saved to $filePath'),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save image: $e'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Flood Fill with Posterization')),
      body: Center(
        child: displayedImageBytes == null
            ? CircularProgressIndicator()
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 300,
                    child: Slider(
                      value: tolerance,
                      min: 0,
                      max: 120,
                      divisions: 120,
                      label: tolerance.toStringAsFixed(1),
                      onChanged: (value) {
                        setState(() {
                          tolerance = value;
                        });
                      },
                    ),
                  ),
                  GestureDetector(
                    onTapDown: (details) => onImageTap(context, details),
                    child: Image.memory(
                      displayedImageBytes!,
                      key: _imageKey,
                      fit: BoxFit.contain,
                    ),
                  ),
                ],
              ),
      ),
      // Two Floating Action Buttons: one to apply blur, one to download.
      floatingActionButton: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            onPressed: applyGaussianBlur,
            tooltip: 'Apply Gaussian Blur',
            child: Icon(Icons.blur_on),
          ),
          SizedBox(width: 16),
          FloatingActionButton(
            onPressed: saveImage,
            tooltip: 'Download PNG',
            child: Icon(Icons.download),
          ),
        ],
      ),
    );
  }
}
