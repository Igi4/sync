import 'package:sync/client.dart';
import 'package:sync/common.dart';
import "package:clean_data/clean_data.dart";
import 'dart:async';
import 'dart:html';

LIElement createListElement(person, persons) {
  TextInputElement name = new TextInputElement()
  ..className = "_id-${person["_id"]}-${persons.collectionName}-name"
  ..value = "${person["name"]}";

  TextInputElement age = new TextInputElement()
  ..className = "_id-${person["_id"]}-${persons.collectionName}-age"
  ..value = "${person["age"]}";

  ButtonElement save = new ButtonElement()
  ..text = "save"
  ..className = "save-button"
  ..dataset["_id"] = person["_id"]
  ..onClick.listen((MouseEvent event) {
    ButtonElement e = event.toElement;
    String _id = e.dataset["_id"];
    DataMap pers = persons.collection.firstWhere((d) => d["_id"] == _id);

    InputElement name = querySelector("._id-${person["_id"]}-${persons.collectionName}-name");
    InputElement age = querySelector("._id-${person["_id"]}-${persons.collectionName}-age");

    if (pers != null) {
      pers["name"] = name.value;
      pers["age"] = int.parse(age.value);
    }
  });

  ButtonElement delete = new ButtonElement()
  ..text = "delete"
  ..dataset["_id"] = person["_id"]
  ..onClick.listen((MouseEvent event) {
    ButtonElement e = event.toElement;
    String _id = e.dataset["_id"];
    DataMap pers = persons.collection.firstWhere((d) => d["_id"] == _id);

    if (pers != null) {
      persons.collection.remove(pers);
    }
  });

  LIElement li = new LIElement()
  ..className = "_id-${person["_id"]}"
  ..text = "#${person["_id"]}"
  ..dataset["_id"] = person["_id"];

  li.children
  ..add(name)
  ..add(age)
  ..add(save)
  ..add(delete);

  return li;
}

void main() {
  Subscription personsDiff, personsDiff24;
  Connection connection = createHttpConnection("http://0.0.0.0:8080/resources/", new Duration(milliseconds: 50000));

  Subscriber subscriber = new Subscriber(connection);
  subscriber.init().then((_) {
    personsDiff = subscriber.subscribe("persons");
    personsDiff24 = subscriber.subscribe("personsOlderThan24Desc");

    modifier(Element e) {
      TextInputElement te = e.children[1];

      return {
        'age': int.parse(te.value),
        '_id': e.dataset['_id']
      };
    }

    Map<String, Subscription> map = {
        '#list-diff': personsDiff,
        '#list24-diff': personsDiff24
    };

    map.forEach((String sel, Subscription sub) {
      sub.collection.onChange.listen((event) {
        UListElement list = querySelector(sel);

        event.addedItems.forEach((person) {
          list.children.add(createListElement(person, sub));
        });

        event.strictlyChanged.forEach((DataMap person, ChangeSet changes) {
          changes.changedItems.forEach((String key, Change value) {
            InputElement e = querySelector("._id-${person["_id"]}-${sub.collectionName}-${key}");
            if (e != null) {
              e.value = value.newValue.toString();
            }
          });
        });

        event.removedItems.forEach((person) {
          querySelector('$sel > li._id-${person["_id"]}').remove();
        });

        list.children = sub.sortCollecion(list.children, modifier);
      });
    });

    querySelector('#send').onClick.listen((_) {
      InputElement name = querySelector("#name");
      InputElement age = querySelector("#age");

      personsDiff.collection.add(new DataMap.from({
        "name" : name.value,
        "age" : int.parse(age.value)
      }));

      name.value = '';
      age.value = '';
    });
  });
}