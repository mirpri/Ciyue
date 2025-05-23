import "dart:io";

import "package:ciyue/database/app.dart";
import "package:ciyue/dictionary.dart";
import "package:ciyue/main.dart";
import "package:ciyue/pages/main/home.dart";
import "package:ciyue/platform.dart";
import "package:ciyue/src/generated/i18n/app_localizations.dart";
import "package:ciyue/widget/loading_dialog.dart";
import "package:file_selector/file_selector.dart";
import "package:flutter/material.dart";
import "package:go_router/go_router.dart";
import "package:path/path.dart";
import "package:provider/provider.dart";
import "package:url_launcher/url_launcher.dart";

late VoidCallback updateManageDictionariesPage;

class ManageDictionaries extends StatefulWidget {
  const ManageDictionaries({super.key});

  @override
  State<ManageDictionaries> createState() => ManageDictionariesState();
}

class ManageDictionariesState extends State<ManageDictionaries> {
  var dictionaries = dictionaryListDao.all();

  Future<void> addGroup(String value, BuildContext context) async {
    if (value.isNotEmpty) {
      await dictGroupDao.addGroup(value, []);
      await dictManager.updateGroupList();
      if (context.mounted) {
        context.pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(leading: buildReturnButton(context), actions: [
        if (Platform.isAndroid) buildUpdateButton(),
        buildInfoButton(context),
        buildAddButton(context)
      ]),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: buildBody(context),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          showDialog(
            context: context,
            builder: (context) => _buildGroupDialog(context),
          );
        },
        child: const Icon(Icons.group),
      ),
    );
  }

  IconButton buildAddButton(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.add),
      onPressed: () {
        if (Platform.isAndroid) {
          PlatformMethod.openDirectory();
        } else {
          selectMdxFile(context);
        }
      },
    );
  }

  FutureBuilder<List<DictionaryListData>> buildBody(BuildContext context) {
    return FutureBuilder(
      future: dictionaries,
      builder: (BuildContext context,
          AsyncSnapshot<List<DictionaryListData>> snapshot) {
        final children = <Widget>[];

        if (snapshot.hasData) {
          int index = 0;
          final dicts = snapshot.data!;
          final dictsMap = {for (final dict in dicts) dict.id: dict};
          for (final id in dictManager.dictIds) {
            children.add(buildDictionaryCard(context, dictsMap[id]!, index));
            index += 1;
          }
          for (final dict in dicts) {
            if (!dictManager.contain(dict.id)) {
              children.add(buildDictionaryCard(context, dict, index));
              index += 1;
            }
          }
        }

        if (children.isEmpty) {
          return Center(child: Text(AppLocalizations.of(context)!.empty));
        } else {
          return ReorderableListView(
            buildDefaultDragHandles: false,
            onReorder: (oldIndex, newIndex) async {
              if (oldIndex < newIndex) {
                newIndex -= 1;
              }

              final dicts = await dictionaries;
              final dict = dicts.removeAt(oldIndex);
              dicts.insert(newIndex, dict);
              if (dictManager.contain(dict.id)) {
                await dictGroupDao.updateDictIds(dictManager.groupId, [
                  for (final dict in dicts)
                    if (dictManager.contain(dict.id)) dict.id
                ]);
                await dictManager.updateDictIds();
              }

              setState(() {});
            },
            children: children,
          );
        }
      },
    );
  }

  Card buildDictionaryCard(
      BuildContext context, DictionaryListData dictionary, int index) {
    final colorScheme = Theme.of(context).colorScheme;
    final title = dictionary.alias ??
        (dictManager.contain(dictionary.id)
            ? dictManager.dicts[dictionary.id]!.title
            : basename(dictionary.path));

    return Card(
      key: ValueKey(dictionary.id),
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      color: colorScheme.onInverseSurface,
      child: GestureDetector(
          onLongPress: () {
            showDialog(
              context: context,
              builder: (BuildContext context) {
                return SimpleDialog(
                  title: Text(title),
                  children: <Widget>[
                    SimpleDialogOption(
                      onPressed: () {
                        context.pop();
                        context.push("/properties", extra: {
                          "path": dictionary.path,
                        });
                      },
                      child: ListTile(
                        leading: Icon(Icons.settings),
                        title: Text(AppLocalizations.of(context)!.properties),
                      ),
                    ),
                    SimpleDialogOption(
                      onPressed: () async {
                        if (dictManager.contain(dictionary.id)) {
                          await dictManager.close(dictionary.id);

                          final dictIds = [
                            for (final dict in dictManager.dicts.values) dict.id
                          ];

                          await dictGroupDao.updateDictIds(
                              dictManager.groupId, dictIds);
                          await dictManager.updateDictIds();
                        }

                        final tmpDict = Mdict(path: dictionary.path);
                        await tmpDict.init();
                        await tmpDict.removeDictionary();
                        await tmpDict.close();

                        updateDictionaries();

                        if (context.mounted) context.pop();
                      },
                      child: ListTile(
                        leading: Icon(Icons.delete),
                        title: Text(AppLocalizations.of(context)!.remove),
                      ),
                    ),
                    SimpleDialogOption(
                      onPressed: () {
                        context.pop();
                        context.push("/description/${dictionary.id}");
                      },
                      child: ListTile(
                        leading: Icon(Icons.info),
                        title: Text(AppLocalizations.of(context)!.description),
                      ),
                    ),
                    SimpleDialogOption(
                      onPressed: () {
                        context.pop();
                        context.push("/settings/${dictionary.id}");
                      },
                      child: ListTile(
                        leading: Icon(Icons.settings),
                        title: Text(AppLocalizations.of(context)!.settings),
                      ),
                    ),
                    SimpleDialogOption(
                      onPressed: () {
                        context.pop();
                        showDialog(
                          context: context,
                          builder: (context) {
                            final controller = TextEditingController();
                            return AlertDialog(
                              title: Text(
                                  AppLocalizations.of(context)!.titleAlias),
                              content: TextField(
                                controller: controller..text = title,
                                autofocus: true,
                                onSubmitted: (value) async {
                                  await updateAlias(value, dictionary, context);
                                },
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () {
                                    dictManager.dicts[dictionary.id]!
                                        .setDefaultTitle();
                                    controller.text =
                                        dictManager.dicts[dictionary.id]!.title;
                                    setState(() {});
                                  },
                                  child: Text(
                                      AppLocalizations.of(context)!.default_),
                                ),
                                TextButton(
                                  onPressed: () => context.pop(),
                                  child:
                                      Text(AppLocalizations.of(context)!.close),
                                ),
                                TextButton(
                                    onPressed: () async {
                                      await updateAlias(
                                          controller.text, dictionary, context);
                                    },
                                    child: Text(
                                        AppLocalizations.of(context)!.confirm)),
                              ],
                            );
                          },
                        );
                      },
                      child: ListTile(
                        leading: Icon(Icons.title),
                        title: Text(AppLocalizations.of(context)!.titleAlias),
                      ),
                    ),
                  ],
                );
              },
            );
          },
          child: CheckboxListTile(
            title: Text(title),
            value: dictManager.contain(dictionary.id),
            secondary: ReorderableDragStartListener(
                index: index,
                child:
                    IconButton(icon: Icon(Icons.reorder), onPressed: () => {})),
            onChanged: (bool? value) async {
              if (value == true) {
                await dictManager.add(dictionary.path);
              } else {
                await dictManager.close(dictionary.id);
              }
              await dictGroupDao.updateDictIds(dictManager.groupId,
                  [for (final dict in dictManager.dicts.values) dict.id]);
              await dictManager.updateDictIds();

              setState(() {});
              if (context.mounted) context.read<HomeModel>().update();
            },
          )),
    );
  }

  IconButton? buildGroupDeleteButton(
      BuildContext context, DictGroupData group) {
    if (group.name == "Default") {
      return null;
    }

    return IconButton(
      icon: const Icon(Icons.delete),
      onPressed: () async {
        if (group.id == dictManager.groupId) {
          if (group.id == dictManager.groups.last.id) {
            await dictManager.setCurrentGroup(
                dictManager.groups[dictManager.groups.length - 2].id);
          } else {
            final index =
                dictManager.groups.indexWhere((g) => g.id == group.id);
            await dictManager.setCurrentGroup(dictManager.groups[index + 1].id);
          }
        }

        await dictGroupDao.removeGroup(group.id);
        await dictManager.updateGroupList();

        if (context.mounted) context.pop();
      },
    );
  }

  IconButton buildInfoButton(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.info),
      onPressed: () {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(AppLocalizations.of(context)!.recommendedDictionaries),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: Text(
                      AppLocalizations.of(context)!.recommendedDictionaries),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => launchUrl(Uri.parse(
                      "https://github.com/mumu-lhl/Ciyue/wiki#recommended-dictionaries")),
                ),
                ListTile(
                  title: const Text("FreeMDict Cloud"),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => launchUrl(Uri.parse(
                      "https://cloud.freemdict.com/index.php/s/pgKcDcbSDTCzXCs")),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => context.pop(),
                child: Text(AppLocalizations.of(context)!.close),
              ),
            ],
          ),
        );
      },
    );
  }

  IconButton buildReturnButton(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () {
        context.pop();
      },
    );
  }

  IconButton buildUpdateButton() {
    return IconButton(
      icon: Icon(Icons.refresh),
      onPressed: () {
        PlatformMethod.updateDictionaries();
      },
    );
  }

  @override
  void initState() {
    super.initState();

    updateManageDictionariesPage = updateDictionaries;
  }

  Future<void> selectMdxFile(BuildContext context) async {
    const XTypeGroup typeGroup = XTypeGroup(
      label: "MDX File",
      extensions: <String>["mdx"],
    );

    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    var path = file?.path;

    if (path != null) {
      if (context.mounted) {
        showLoadingDialog(context, text: "Copying files...");
      }

      late final Mdict tmpDict;
      try {
        path = setExtension(path, "");
        tmpDict = Mdict(path: path);
        if (await tmpDict.add()) {
          await tmpDict.close();
        }
      } catch (e) {
        await tmpDict.close();
        if (context.mounted) {
          final snackBar =
              SnackBar(content: Text(AppLocalizations.of(context)!.notSupport));
          ScaffoldMessenger.of(context).showSnackBar(snackBar);
        }
      }

      updateDictionaries();

      if (context.mounted) context.pop();
    }
  }

  void showPermissionDenied(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(AppLocalizations.of(context)!.permissionDenied),
      action: SnackBarAction(
          label: AppLocalizations.of(context)!.close, onPressed: () {}),
    ));
  }

  Future<void> updateAlias(
      String value, DictionaryListData dictionary, BuildContext context) async {
    if (value.isNotEmpty) {
      dictManager.dicts[dictionary.id]!.title = value;
      await dictionaryListDao.updateAlias(dictionary.id, value);
      updateDictionaries();
      if (context.mounted) {
        context.pop();
      }
    }
  }

  void updateDictionaries() {
    setState(() {
      dictionaries = dictionaryListDao.all();
    });
  }

  Widget _buildGroupDialog(BuildContext context) {
    return AlertDialog(
      title: Text(AppLocalizations.of(context)!.manageGroups),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final group in dictManager.groups)
            RadioListTile(
              title: Text(group.name == "Default"
                  ? AppLocalizations.of(context)!.default_
                  : group.name),
              value: group.id,
              groupValue: dictManager.groupId,
              secondary: buildGroupDeleteButton(context, group),
              onChanged: (int? groupId) async {
                if (groupId != dictManager.groupId) {
                  await dictManager.setCurrentGroup(groupId!);
                  setState(() {});
                }
                if (context.mounted) context.pop();
              },
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => context.pop(),
          child: Text(AppLocalizations.of(context)!.close),
        ),
        TextButton(
          onPressed: () {
            context.pop();
            showDialog(
              context: context,
              builder: (context) {
                final controller = TextEditingController();
                return AlertDialog(
                  title: Text(AppLocalizations.of(context)!.add),
                  content: TextField(
                    controller: controller,
                    autofocus: true,
                    onSubmitted: (String groupName) async {
                      await addGroup(groupName, context);
                    },
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => context.pop(),
                      child: Text(AppLocalizations.of(context)!.close),
                    ),
                    TextButton(
                        onPressed: () async {
                          await addGroup(controller.text, context);
                        },
                        child: Text(AppLocalizations.of(context)!.add)),
                  ],
                );
              },
            );
          },
          child: Text(AppLocalizations.of(context)!.add),
        ),
      ],
    );
  }
}
