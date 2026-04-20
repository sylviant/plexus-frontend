import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:plexus/core/api_config.dart';
import 'package:http/http.dart' as http;
import 'package:go_router/go_router.dart';
import 'dart:convert';

class DisputeScreen extends StatefulWidget {
  final Map<String, dynamic> order;

  const DisputeScreen({required this.order, super.key});

  @override
  State<DisputeScreen> createState() => _DisputeScreenState();
}

class _DisputeScreenState extends State<DisputeScreen> {
  final _descriptionController = TextEditingController();
  String _selectedMotif = 'Produit non conforme';
  
  final List<XFile> _photoFiles = [];
  final List<Uint8List> _photoBytes = [];
  XFile? _videoFile;
  bool _isSubmitting = false;

  final ImagePicker _picker = ImagePicker();

  Future<void> _pickImage() async {
    if (_photoFiles.length >= 3) return;
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (image != null) {
      final bytes = await image.readAsBytes();
      setState(() {
        _photoFiles.add(image);
        _photoBytes.add(bytes);
      });
    }
  }

  Future<void> _pickVideo() async {
    final XFile? video = await _picker.pickVideo(source: ImageSource.gallery);
    if (video != null) {
      setState(() => _videoFile = video);
    }
  }

  Future<void> _submitDispute() async {
    if (_descriptionController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("La description est obligatoire")));
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final String orderId = (widget.order['_id'] ?? widget.order['id'] ?? "").toString();
      
      var request = http.MultipartRequest('POST', Uri.parse('${ApiConfig.baseUrl}/disputes'));
      request.fields['orderId'] = orderId;
      request.fields['motif'] = _selectedMotif;
      request.fields['description'] = _descriptionController.text;

      // Envoi des photos
      for (int i = 0; i < _photoFiles.length; i++) {
        request.files.add(http.MultipartFile.fromBytes(
          'photos', // Le nom du champ doit correspondre au backend (upload.array('photos'))
          _photoBytes[i],
          filename: 'photo_$i.jpg',
        ));
      }

      // Envoi de la vidéo
      if (_videoFile != null) {
        final vBytes = await _videoFile!.readAsBytes();
        request.files.add(http.MultipartFile.fromBytes(
          'video', 
          vBytes,
          filename: 'video.mp4',
        ));
      }

      var streamedResponse = await request.send();
      var res = await http.Response.fromStream(streamedResponse);

      if (res.statusCode == 201 || res.statusCode == 200) {
        if (mounted) {
          context.pop();
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Litige ouvert avec succès."), backgroundColor: Colors.green));
        }
      } else {
        // LOG POUR DEBUGGER LE 500
        debugPrint("SERVER ERROR 500 BODY: ${res.body}");
        throw Exception("Erreur ${res.statusCode}: ${res.body}");
      }
    } catch (e) {
      debugPrint("DISPUTE ERROR: $e");
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Échec : Vérifiez les logs backend")));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Ouvrir un Litige"), backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Motif du litige", style: TextStyle(fontWeight: FontWeight.bold)),
            DropdownButton<String>(
              value: _selectedMotif,
              isExpanded: true,
              items: ['Produit non conforme', 'Endommagé', 'Colis vide'].map((String value) {
                return DropdownMenuItem<String>(value: value, child: Text(value));
              }).toList(),
              onChanged: (v) => setState(() => _selectedMotif = v!),
            ),
            const SizedBox(height: 20),
            const Text("Description détaillée", style: TextStyle(fontWeight: FontWeight.bold)),
            TextField(
              controller: _descriptionController,
              maxLines: 4,
              decoration: const InputDecoration(border: OutlineInputBorder(), hintText: "Détaillez votre problème..."),
            ),
            const SizedBox(height: 20),
            const Text("Preuves Photos (Max 3)", style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              children: [
                ...List.generate(_photoBytes.length, (index) => Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(_photoBytes[index], width: 80, height: 80, fit: BoxFit.cover),
                    ),
                    Positioned(
                      right: -10, top: -10,
                      child: IconButton(icon: const Icon(Icons.cancel, color: Colors.red), onPressed: () => setState(() {
                        _photoFiles.removeAt(index);
                        _photoBytes.removeAt(index);
                      })),
                    ),
                  ],
                )),
                if (_photoFiles.length < 3)
                  GestureDetector(
                    onTap: _pickImage,
                    child: Container(
                      width: 80, height: 80,
                      decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.add_a_photo, color: Colors.grey),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            const Text("Preuve Vidéo", style: TextStyle(fontWeight: FontWeight.bold)),
            if (_videoFile != null)
              ListTile(
                leading: const Icon(Icons.video_collection, color: Colors.blue),
                title: Text(_videoFile!.name, style: const TextStyle(fontSize: 12)),
                trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => setState(() => _videoFile = null)),
              )
            else
              ElevatedButton.icon(onPressed: _pickVideo, icon: const Icon(Icons.videocam), label: const Text("Ajouter une vidéo")),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitDispute,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: _isSubmitting ? const CircularProgressIndicator(color: Colors.white) : const Text("ENVOYER LE LITIGE", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
