import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:xml/xml.dart' as xml;
import 'package:file_picker/file_picker.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:path_provider/path_provider.dart'; // For mobile file saving.

// This import is only available on web. For a production app, consider conditional imports.
import 'dart:html' as html;

class SvgColorizer extends StatefulWidget {
  const SvgColorizer({Key? key}) : super(key: key);

  @override
  State<SvgColorizer> createState() => _SvgColorizerState();
}

class _SvgColorizerState extends State<SvgColorizer> {
  // Holds the root attributes from the <svg> tag.
  String? rootAttributes;
  // Stores each child element's XML as a string.
  List<String> svgElements = [];
  // (Optional) Additional mapping if needed.
  Map<String, String> colorMapping = {};

  // Tracks which element index is being hovered (null if none).
  int? hoveredIndex;

  /// Use file_picker to let the user select an SVG file.
  Future<void> pickSvgFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['svg'],
    );
    if (result != null) {
      String? filePath = kIsWeb ? null : result.files.first.path;
      String fileContents;
      if (filePath != null) {
        fileContents = await File(filePath).readAsString();
      } else if (result.files.first.bytes != null) {
        fileContents = String.fromCharCodes(result.files.first.bytes!);
      } else {
        print("No valid file data found.");
        return;
      }

      try {
        final doc = xml.XmlDocument.parse(fileContents);
        processSvg(doc);
      } catch (e) {
        print("Error parsing SVG: $e");
      }
    }
  }

  /// Process the loaded SVG:
  /// - Extracts the root attributes.
  /// - Stores all descendant element strings.
  void processSvg(xml.XmlNode node) {
    // Get the <svg> root element.
    final svgRoot =
        (node is xml.XmlDocument) ? node.rootElement : node as xml.XmlElement;
    // Build a string of attributes like: width="200" height="200" viewBox="...".
    rootAttributes = svgRoot.attributes
        .map((attr) => '${attr.name}="${attr.value}"')
        .join(' ');
    // Store each descendant element's XML string.
    svgElements = svgRoot.descendantElements
        .map((element) => element.toXmlString())
        .toList();
    setState(() {});
  }

  /// Helper to convert a [Color] to a hex string (e.g. "#rrggbb").
  String colorToHex(Color color) {
    return '#${(color.value & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
  }

  /// Opens a color picker for a given element and updates its fill color.
  Future<void> pickColorForComponent(xml.XmlElement node, int index) async {
    Color initialColor = Color(
      int.parse(
        node.getAttribute('fill')?.replaceFirst('#', '0xff') ?? '0xffffffff',
      ),
    );
    Color selectedColor = initialColor;
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Pick Color for ${node.name.local}'),
          content: SingleChildScrollView(
            child: ColorPicker(
              pickerColor: initialColor,
              onColorChanged: (color) {
                selectedColor = color;
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
    setState(() {
      final hexColor = colorToHex(selectedColor);
      node.setAttribute('fill', hexColor);
      // Update the saved element string.
      svgElements[index] = node.toXmlString();
    });
  }

  /// Constructs the full SVG string.
  ///
  /// If an element is currently hovered, its fill color is temporarily
  /// overridden (for example, to yellow) for highlighting.
  String getEditedSvgString() {
    List<String> newElements = [];
    for (int i = 0; i < svgElements.length; i++) {
      String elementStr = svgElements[i];
      // If this element is hovered, override its fill color.
      if (hoveredIndex != null && hoveredIndex == i) {
        try {
          final element = xml.XmlDocument.parse(elementStr).rootElement;
          // Temporarily set the fill to yellow (you can choose any highlight color).
          element.setAttribute('fill', colorToHex(Colors.yellow));
          elementStr = element.toXmlString();
        } catch (e) {
          print('Error applying highlight to element: $e');
        }
      }
      newElements.add(elementStr);
    }
    return '''
<svg $rootAttributes>
${newElements.join('\n')}
</svg>
''';
  }

  /// Downloads (or saves) the edited SVG.
  Future<void> downloadEditedSvg() async {
    final svgContent = getEditedSvgString();

    if (kIsWeb) {
      // On web: Create a Blob and an invisible download link.
      final bytes = utf8.encode(svgContent);
      final blob = html.Blob([bytes], 'image/svg+xml');
      final url = html.Url.createObjectUrlFromBlob(blob);
      final anchor = html.AnchorElement(href: url)
        ..style.display = 'none'
        ..download = 'edited.svg';
      html.document.body!.append(anchor);
      anchor.click();
      anchor.remove();
      html.Url.revokeObjectUrl(url);
    } else {
      // On mobile: Save the file to the documents directory.
      final directory = await getApplicationDocumentsDirectory();
      final path = '${directory.path}/edited.svg';
      final file = File(path);
      await file.writeAsString(svgContent);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('SVG saved to $path')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('SVG Colorizer'),
        actions: [
          IconButton(
            icon: Icon(Icons.folder_open),
            tooltip: 'Select SVG File',
            onPressed: pickSvgFile,
          ),
        ],
      ),
      body: Row(
        children: [
          // Left panel: List of SVG components.
          Container(
            width: 250,
            color: Colors.grey[200],
            child: ListView.builder(
              itemCount: svgElements.length,
              itemBuilder: (context, index) {
                final comp = svgElements[index];
                final node = xml.XmlDocument.parse(comp).rootElement;
                Color displayColor = Color(
                  int.parse(
                    node.getAttribute('fill')?.replaceFirst('#', '0xff') ??
                        '0xffffffff',
                  ),
                );
                // Wrap the ListTile in a MouseRegion to detect hover events.
                return MouseRegion(
                  onEnter: (_) {
                    setState(() {
                      hoveredIndex = index;
                    });
                  },
                  onExit: (_) {
                    setState(() {
                      hoveredIndex = null;
                    });
                  },
                  child: ListTile(
                    title: Text('${node.name.local}'),
                    trailing: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: displayColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black38),
                      ),
                    ),
                    onTap: () {
                      pickColorForComponent(node, index);
                    },
                  ),
                );
              },
            ),
          ),
          VerticalDivider(width: 1),
          // Right panel: Render the (possibly highlighted) SVG.
          Expanded(
            child: SingleChildScrollView(
              child: Container(
                padding: EdgeInsets.all(8),
                child: SvgPicture.string(
                  getEditedSvgString(),
                  placeholderBuilder: (context) =>
                      Center(child: CircularProgressIndicator()),
                  errorBuilder: (context, error, stackTrace) {
                    return Center(child: Text('Error loading SVG: $error'));
                  },
                ),
              ),
            ),
          ),
        ],
      ),
      // Floating action button to download the edited SVG.
      floatingActionButton: FloatingActionButton(
        onPressed: downloadEditedSvg,
        tooltip: 'Download Edited SVG',
        child: Icon(Icons.download),
      ),
    );
  }
}
