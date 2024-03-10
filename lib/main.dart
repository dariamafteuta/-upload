import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(MyApp());

Future<void> saveProgress(double progress) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setDouble('uploadProgress', progress);
}

Future<void> resetSp() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove("uploadedChunks");
  await prefs.remove("uploadProgress");
}

Future<double> loadProgress() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove("uploadedChunks");
  await prefs.remove("uploadProgress");
  return prefs.getDouble('uploadProgress') ?? 0.0;
}

Future<void> saveUploadedChunks(List<bool> uploadedChunks) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('uploadedChunks', uploadedChunks.join(','));
}

Future<List<bool>> loadUploadedChunks(int totalChunks) async {
  final prefs = await SharedPreferences.getInstance();
  String savedChunks = prefs.getString('uploadedChunks') ?? '';
  if (savedChunks.isEmpty) return List.generate(totalChunks, (_) => false);
  List<String> chunksStr = savedChunks.split(',');
  return chunksStr.map((e) => e == 'true').toList();
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: FileUploadPage(),
    );
  }
}

class FileUploadManager {
  Dio dio = Dio();
  // String uploadURL = 'https://6f93-80-94-250-238.ngrok-free.app/upload_chunk';
  String uploadURL = 'http://localhost:8080/upload_chunk';
  int chunkSize = 1024 * 1024; // Размер части файла, например 1 МБ
  late List<bool> uploadedChunks; // Список загруженных частей
  File? file;
  Function(double)? onProgressUpdate;

  FileUploadManager({this.onProgressUpdate});

  Future<void> uploadFile(File file) async {
    this.file = file;
    int totalChunks = (file.lengthSync() / chunkSize).ceil();
    uploadedChunks = await loadUploadedChunks(totalChunks);
    int uploadedChunksCount = uploadedChunks.where((e) => e).length;
    // [todo]
    // uploadedChunks = List.generate(totalChunks, (_) => false); // Переинициализация списка

    for (int i = 0; i < totalChunks; i++) {
      if (!uploadedChunks[i]) {
        File chunkFile = await _createChunkFile(file, i);
        bool uploadSuccess = await _uploadChunk(chunkFile, file.path.split('/').last, i, totalChunks);
        await chunkFile.delete();
        if (uploadSuccess) {
          uploadedChunks[i] = true;
          saveUploadedChunks(uploadedChunks);
          uploadedChunksCount++;
          onProgressUpdate?.call(uploadedChunksCount / totalChunks);
        }
      }
    }
    if (uploadedChunksCount == totalChunks) {
      saveProgress(0.0);
      saveUploadedChunks(List.generate(totalChunks, (_) => false));
      resetSp();
      onProgressUpdate?.call(0);
    }
  }

  Future<File> _createChunkFile(File file, int chunkIndex) async {
    final tempDir = await getTemporaryDirectory();
    final chunkFile = File('${tempDir.path}/chunk_$chunkIndex.tmp');
    final chunk = await file.openSync();
    chunk.setPositionSync(chunkIndex * chunkSize);
    final chunkData = chunk.readSync(chunkSize);
    chunkFile.writeAsBytesSync(chunkData);
    chunk.closeSync();
    return chunkFile;
  }

  Future<bool> _uploadChunk(
      File chunkFile, String originalfilename, int chunkIndex, int totalChunks) async {
    FormData formData = FormData.fromMap({
      'originalFileName': originalfilename,
      'file': await MultipartFile.fromFile(chunkFile.path,
          filename: 'chunk_$chunkIndex'),
      'index': chunkIndex+1,
      'totalChunks': totalChunks, // Добавляем общее количество частей файла
    });

    try {
      await dio.post(uploadURL, data: formData);
      return true;
    } catch (e) {
      print('Error uploading chunk $chunkIndex: $e');
      return false;
    }
  }
}

class FileUploadPage extends StatefulWidget {
  @override
  _FileUploadPageState createState() => _FileUploadPageState();
}

class _FileUploadPageState extends State<FileUploadPage> {
  double _uploadProgress = 0;
  bool _isUploading = false;
  List<String> _files = [];

  @override
  void initState() {
    super.initState();
    loadProgress().then((value) {
      setState(() {
        _uploadProgress = value;
        _isUploading = value > 0.0 && value < 1.0;
      });
    });
    _loadFiles();
  }

  void _loadFiles() async {
    try {
      List<String> files = await fetchFileList();
      setState(() {
        print(files);
        _files = files;
      });
    } catch (e) {
      // Обработка ошибок
      print("Error loading files: $e");
    }
  }

  Future<List<String>> fetchFileList() async {
    final response = await Dio().get('http://localhost:8080/list_files');
    if (response.statusCode == 200) {
      // Предполагаем, что ответ сервера - это JSON строка, представляющая список.
      final List<dynamic> fileList = response.data;
      return fileList
          .cast<String>(); // Преобразуем каждый элемент списка в String.
    } else {
      throw Exception('Failed to load file list');
    }
  }

  void _updateUploadProgress(double progress) {
    saveProgress(progress);
    setState(() {
      _uploadProgress = progress;
      if (progress >= 1) {
        _isUploading = false;
      }
    });
  }

  void _pickAndUploadFile() async {
    if (_isUploading) return;

    setState(() {
      _isUploading = true;
    });

    final uploadManager = FileUploadManager(
      onProgressUpdate: _updateUploadProgress,
    );
    if (_uploadProgress > 0.0 && _uploadProgress < 1.0) {
      await uploadManager.uploadFile(uploadManager.file!);
    } else {
      FilePickerResult? result = await FilePicker.platform.pickFiles();
      if (result != null) {
        PlatformFile platformFile = result.files.first;
        File file = File(platformFile.path!);
        uploadManager.file = file;
        await uploadManager.uploadFile(file);
      }
    }

    setState(() {
      _isUploading = false;
    });

    _loadFiles();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Chunked File Upload')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _isUploading
                ? CircularProgressIndicator()
                : ElevatedButton.icon(
                    icon: Icon(_uploadProgress > 0.0 && _uploadProgress < 1.0
                        ? Icons.play_arrow
                        : Icons.file_upload),
                    onPressed: _pickAndUploadFile,
                    label: Text(_uploadProgress > 0.0 && _uploadProgress < 1.0
                        ? 'Resume Upload'
                        : 'Pick and Upload File'),
                  ),
            SizedBox(height: 20),
            LinearProgressIndicator(value: _uploadProgress),
            Text('${(_uploadProgress * 100).toStringAsFixed(2)} %'),
            Expanded(
              child: ListView.builder(
                itemCount: _files.length,
                itemBuilder: (context, index) {
                  return Card(
                    margin: EdgeInsets.all(8.0),
                    child: ListTile(
                      leading: Icon(Icons.insert_drive_file),
                      title: Text(_files[index]),
                      onTap: () {
                        // Здесь может быть ваш код для скачивания или открытия файла
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
