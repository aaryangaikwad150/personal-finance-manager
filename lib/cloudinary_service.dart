import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'config/api_key.dart';

class CloudinaryService {
  static Future<String?> _uploadBytes(Uint8List bytes, String filename) async {
    try {
      final uri = Uri.parse('https://api.cloudinary.com/v1_1/${ApiKeys.cloudinaryCloudName}/image/upload');
      final request = http.MultipartRequest('POST', uri);
      request.fields['upload_preset'] = ApiKeys.cloudinaryUploadPreset;
      request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));

      final response = await request.send();
      if (response.statusCode == 200) {
        final body = await response.stream.bytesToString();
        final data = jsonDecode(body);
        return data['secure_url'] as String?;
      }
    } catch (e) {
      // fall through
    }
    return null;
  }

  /// Opens the browser's file picker and uploads the chosen image to Cloudinary.
  static Future<String?> pickAndUpload() async {
    final picker = ImagePicker();
    final XFile? picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (picked == null) return null;
    final bytes = await picked.readAsBytes();
    return _uploadBytes(bytes, picked.name);
  }
}