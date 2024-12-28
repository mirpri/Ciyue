import "dart:io";

import "package:dict_reader/dict_reader.dart";
import "package:drift/drift.dart";
import "package:path/path.dart";
import "package:path_provider/path_provider.dart";

import "database/dictionary.dart";
import "main.dart";

class DictManager {
  final Map<int, Mdict> dicts = {};

  bool get isEmpty => dicts.isEmpty;

  bool contain(int id) => dicts.keys.contains(id);

  Future<void> add(String path) async {
    final dict = Mdict(path: path);
    await dict.init();
    dicts[dict.id] = dict;
  }

  Future<void> remove(int id) async {
    await dicts[id]!.removeDictionary();
    dicts.remove(id);
  }
}

final dictManager = DictManager();

class Mdict {
  late final int id;
  final String path;
  String? fontName;
  String? fontPath;
  String? backupPath;
  late final DictionaryDatabase db;
  late final DictReader reader;
  DictReader? readerResource;

  Mdict({required this.path});

  Future<void> init() async {
    id = await mainDatabase.getId(path);

    reader = DictReader("$path.mdx");
    await reader.init(false);

    try {
      readerResource = DictReader("$path.mdd");
      await readerResource!.init(false);
    } catch (e) {
      readerResource = null;
    }

    db = dictionaryDatabase(id);

    final fontPath = await mainDatabase.getFontPath(id);
    customFont(fontPath);

    final backupPath = await mainDatabase.getBackupPath(id);
    customBackupPath(backupPath);
  }

  Future<void> close() async {
    await db.close();
  }

  Future<bool> add() async {
    try {
      await mainDatabase.getId(path);
      return false;
      // ignore: empty_catches
    } catch (e) {}

    await _initDictReader(path);

    await prefs.setString("currentDictionaryPath", path);

    await mainDatabase.add(path);

    id = await mainDatabase.getId(path);
    db = dictionaryDatabase(id);

    await _addWords();

    if (readerResource != null) await _addResource();

    customFont(null);
    customBackupPath(null);

    return true;
  }

  Future<void> customBackupPath(String? path) async {
    backupPath = path;
    await mainDatabase.updateBackup(id, path);
  }

  Future<void> customFont(String? path) async {
    fontPath = path;
    if (path == null) {
      fontName = null;
    } else {
      fontName = basename(path);
    }

    await mainDatabase.updateFont(id, path);
  }

  Future<String> readWord(String word) async {
    late DictionaryData data;
    try {
      data = await db.getOffset(word);
    } catch (e) {
      data = await db.getOffset(word.toLowerCase());
    }

    String content = await reader.readOne(data.blockOffset, data.startOffset,
        data.endOffset, data.compressedSize);

    if (content.startsWith("@@@LINK=")) {
      // 8: remove @@@LINK=
      // content.length - 3: remove \r\n\x00
      data = await db
          .getOffset(content.substring(8, content.length - 3).trimRight());
      content = await reader.readOne(data.blockOffset, data.startOffset,
          data.endOffset, data.compressedSize);
    }

    return content;
  }

  Future<void> removeDictionary() async {
    await prefs.remove("currentDictionaryPath");

    await db.close();
    final databasePath = join((await getApplicationDocumentsDirectory()).path,
        "dictionary_$id.sqlite");
    final file = File(databasePath);
    await file.delete();

    await mainDatabase.remove(path);
  }

  Future<void> _addResource() async {
    final resourceList = <ResourceCompanion>[];
    var number = 0;

    await for (final (
          key,
          (blockOffset, startOffset, endOffset, compressedSize)
        ) in readerResource!.read()) {
      resourceList.add(ResourceCompanion(
          key: Value(key),
          blockOffset: Value(blockOffset),
          startOffset: Value(startOffset),
          endOffset: Value(endOffset),
          compressedSize: Value(compressedSize)));
      number++;

      if (number == 50000) {
        number = 0;
        await db.insertResource(resourceList);
        resourceList.clear();
      }
    }

    if (resourceList.isNotEmpty) {
      await db.insertResource(resourceList);
    }
  }

  Future<void> _addWords() async {
    final wordList = <DictionaryCompanion>[];
    var number = 0;

    await for (final (
          key,
          (blockOffset, startOffset, endOffset, compressedSize)
        ) in reader.read()) {
      wordList.add(DictionaryCompanion(
          key: Value(key),
          blockOffset: Value(blockOffset),
          startOffset: Value(startOffset),
          endOffset: Value(endOffset),
          compressedSize: Value(compressedSize)));
      number++;

      if (number == 50000) {
        number = 0;
        await db.insertWords(wordList);
        wordList.clear();
      }
    }

    if (wordList.isNotEmpty) {
      await db.insertWords(wordList);
    }
  }

  Future<void> _initDictReader(String path, {bool readKey = true}) async {
    final dictReaderTemp = DictReader("$path.mdx");
    await dictReaderTemp.init(readKey);

    reader = dictReaderTemp;

    try {
      readerResource = DictReader("$path.mdd");
      await readerResource!.init(readKey);
    } catch (e) {
      readerResource = null;
    }
  }
}
