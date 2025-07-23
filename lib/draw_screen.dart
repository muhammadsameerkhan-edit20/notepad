import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:signature/signature.dart';

class DrawScreen extends StatefulWidget {
  const DrawScreen({super.key});

  @override
  State<DrawScreen> createState() => _DrawScreenState();
}

class _DrawScreenState extends State<DrawScreen> {
  final SignatureController _controller = SignatureController(
    penStrokeWidth: 3,
    penColor: Colors.white,
    exportBackgroundColor: Colors.black,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Draw'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: () async {
              if (_controller.isNotEmpty) {
                final image = await _controller.toPngBytes();
                Navigator.pop(context, image);
              } else {
                Navigator.pop(context, null);
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Signature(
              controller: _controller,
              backgroundColor: Colors.black,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: const Icon(Icons.undo, color: Colors.white),
                onPressed: () => _controller.undo(),
              ),
              IconButton(
                icon: const Icon(Icons.redo, color: Colors.white),
                onPressed: () => _controller.redo(),
              ),
              IconButton(
                icon: const Icon(Icons.clear, color: Colors.white),
                onPressed: () => _controller.clear(),
              ),
            ],
          ),
        ],
      ),
    );
  }
} 