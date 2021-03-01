import 'dart:convert';

import 'package:fhir/r4.dart';
import 'package:research_package/model.dart';

import '../extensions/safe_access_extensions.dart';

class DataFormatException implements Exception {
  /// A human-readable message
  final String message;

  /// The offending data element
  final dynamic element;

  /// A throwable
  final dynamic? cause;
  DataFormatException(this.message, this.element, [this.cause]);
}

class RPFhirQuestionnaire {
  RPFhirQuestionnaire.fromString(String stringFhirQuestionnaire)
      : _questionnaire =
            Questionnaire.fromJson(json.decode(stringFhirQuestionnaire));

  RPFhirQuestionnaire.fromJson(Map<String, dynamic> jsonFhirQuestionnaire)
      : _questionnaire = Questionnaire.fromJson(jsonFhirQuestionnaire);

  RPFhirQuestionnaire.fromQuestionnaire(Questionnaire fhirQuestionnaire)
      : _questionnaire = fhirQuestionnaire;

  final Questionnaire _questionnaire;
  final double _minDecimal = 0;
  final double _maxDecimal = 999999999999; // 1 trillion - 1
  final int _minInt = 0;
  final int _maxInt = 999999999; // 1 billion - 1

  RPOrderedTask surveyTask() {
    return RPOrderedTask(
      'surveyTaskID',
      [..._rpStepsFromFhirQuestionnaire(), completionStep()],
    );
  }

  List<RPStep> _rpStepsFromFhirQuestionnaire() {
    final toplevelSteps = <RPStep>[];
    _questionnaire.item!.forEach((item) {
      toplevelSteps.addAll(_buildSteps(item, 0));
    });
    return toplevelSteps;
  }

  List<RPStep> _buildSteps(QuestionnaireItem item, int level) {
    var steps = <RPStep>[];

    switch (item.type) {
      case QuestionnaireItemType.group:
        {
          steps.add(RPInstructionStep(
            identifier: item.linkId,
            detailText:
                'Please fill out this survey.\n\nIn this survey the questions will come after each other in a given order. You still have the chance to skip some of them, though.',
            title: item.code?.safeDisplay,
          )..text = item.text);

          item.item!.forEach((groupItem) {
            steps.addAll(_buildSteps(groupItem, level + 1));
          });
        }
        break;
      case QuestionnaireItemType.display:
        {}
        break;
      case QuestionnaireItemType.boolean:
      case QuestionnaireItemType.decimal:
      case QuestionnaireItemType.integer:
      // case QuestionnaireItemType.date:
      // case QuestionnaireItemType.datetime:
      // case QuestionnaireItemType.time:
      case QuestionnaireItemType.string:
      case QuestionnaireItemType.text:
      // case QuestionnaireItemType.url:
      case QuestionnaireItemType.choice:
      // case QuestionnaireItemType.open_choice:
      // case QuestionnaireItemType.attachment:
      // case QuestionnaireItemType.reference:
      // case QuestionnaireItemType.quantity:
      case QuestionnaireItemType.choice:
        steps.addAll(_buildQuestionSteps(item, level));
        break;
      default:
        print('Unsupported item type: ${item.type.toString()}');
    }
    return steps;
  }

  List<RPQuestionStep> _buildQuestionSteps(QuestionnaireItem item, int level) {
    final steps = <RPQuestionStep>[];

    final optional = !(item.required_?.value ?? true);

    switch (item.type) {
      case QuestionnaireItemType.boolean:
        {
          steps.add(RPQuestionStep.withAnswerFormat(
              item.linkId,
              _getText(item),
              RPChoiceAnswerFormat.withParams(
                ChoiceAnswerStyle.SingleChoice,
                [
                  RPChoice.withParams('True', 0),
                  RPChoice.withParams('False', 1)
                ],
              ),
              optional: optional));
        }
        break;
      case QuestionnaireItemType.decimal:
        {
          steps.add(RPQuestionStep.withAnswerFormat(
              item.linkId,
              _getText(item),
              // TODO: make PR for research_package to allow doubles
              RPIntegerAnswerFormat.withParams(_minInt, _maxInt),
              optional: optional));
          // Unfortunately, surveys are using "Decimal" when they are clearly expecting integers.
        }
        break;
      case QuestionnaireItemType.integer:
        {
          steps.add(RPQuestionStep.withAnswerFormat(item.linkId, _getText(item),
              RPIntegerAnswerFormat.withParams(_minInt, _maxInt),
              optional: optional));
        }
        break;

      /// Short (few words to short sentence) free-text answer
      case QuestionnaireItemType.string:
        {
          steps.add(RPQuestionStep.withAnswerFormat(
              item.linkId,
              _getText(item),
              RPChoiceAnswerFormat.withParams(ChoiceAnswerStyle.SingleChoice,
                  [RPChoice.withParams(_getText(item), 0, true)]),
              optional: optional));
        }
        break;

      ///  Long (potentially multi-paragraph) free-text answer
      case QuestionnaireItemType.text:
        {
          steps.add(RPQuestionStep.withAnswerFormat(
              item.linkId,
              _getText(item),
              RPChoiceAnswerFormat.withParams(ChoiceAnswerStyle.SingleChoice,
                  [RPChoice.withParams(_getText(item), 0, true)]),
              optional: optional));
        }
        break;
      case QuestionnaireItemType.choice:
        {
          steps.add(RPQuestionStep.withAnswerFormat(
              item.linkId, _getText(item), _buildChoiceAnswers(item),
              optional: optional));
        }
        break;

      default:
        print('Unsupported question item type: ${item.type.toString()}');
    }
    return steps;
  }

  /// checks if the textElement has a valueString, if that's null, it checks for
  /// item.text, then item.linkId and finally changes the item to a String and
  /// returns that value
  String _getText(QuestionnaireItem item) {
    return item.textElement?.extension_?.elementAt(0).valueString ??
        item.text ??
        item.linkId ??
        item.toString();
  }

  RPAnswerFormat _buildChoiceAnswers(QuestionnaireItem item) {
    var choices = <RPChoice>[];

    if (item.answerValueSet != null) {
      final key = item.answerValueSet!.value!
          .toString()
          .substring(1); // Strip off leading '#'
      var i = 0;
      final List<ValueSetConcept>? valueSetConcepts = (_questionnaire.contained
              ?.firstWhere((item) => (key == item.id?.toString())) as ValueSet?)
          ?.compose
          ?.include
          .firstOrNull
          ?.concept;

      if (valueSetConcepts == null)
        throw DataFormatException(
            'Questionnaire does not contain referenced ValueSet $key',
            _questionnaire);

      valueSetConcepts.forEach((item) {
        choices.add(RPChoice.withParams(item.display, i++));
      });
    } else {
      var i = 0;
      // TODO: Don't forget to put the real values back into the response...
      item.answerOption?.forEach((choice) {
        choices.add(RPChoice.withParams(choice.safeDisplay, i++));
      });
    }

    return RPChoiceAnswerFormat.withParams(
        ChoiceAnswerStyle.SingleChoice, choices);
  }

  QuestionnaireResponseItem _fromGroupItem(
      QuestionnaireItem item, RPTaskResult result) {
    final nestedItems = <QuestionnaireResponseItem>[];
    item.item!.forEach((nestedItem) {
      if (nestedItem.type == QuestionnaireItemType.group) {
        nestedItems.add(_fromGroupItem(nestedItem, result));
      } else {
        final responseItem = _fromQuestionItem(nestedItem, result);
        if (responseItem != null) nestedItems.add(responseItem);
      }
    });
    return QuestionnaireResponseItem(
        linkId: item.linkId, text: item.text, item: nestedItems);
  }

  QuestionnaireResponseItem? _fromQuestionItem(
      QuestionnaireItem item, RPTaskResult result) {
    // TODO: Support more response types
    final RPStepResult? resultStep = result.results[item.linkId];
    if (resultStep == null) {
      print('No result found for linkId ${item.linkId}');
      return null;
    }
    final resultForIdentifier = resultStep.getResultForIdentifier('answer');
    if (resultForIdentifier == null) {
      print('No answer for ${item.linkId}');
      return QuestionnaireResponseItem(
          linkId: item.linkId, text: resultStep.questionTitle, answer: []);
    }
    switch (item.type) {
      case QuestionnaireItemType.choice:
        final rpChoice = (resultForIdentifier as List<RPChoice>).first;
        return QuestionnaireResponseItem(
            linkId: item.linkId,
            text: resultStep.questionTitle,
            answer: [
              QuestionnaireResponseAnswer(valueString: rpChoice.text)
            ]); // TODO: Use Coding?
      case QuestionnaireItemType.decimal:
        return QuestionnaireResponseItem(
            linkId: item.linkId,
            text: resultStep.questionTitle,
            answer: [
              QuestionnaireResponseAnswer(
                  valueDecimal: Decimal(resultForIdentifier as String))
            ]);
      case QuestionnaireItemType.string:
        final rpChoice = (resultForIdentifier as List<RPChoice>).first;
        return QuestionnaireResponseItem(
            linkId: item.linkId,
            text: resultStep.questionTitle,
            answer: [QuestionnaireResponseAnswer(valueString: rpChoice.text)]);
      default:
        print('${item.type} not supported');
        return QuestionnaireResponseItem(linkId: item.linkId);
    }
  }

  void _addResponseItemToDiv(
      StringBuffer div, QuestionnaireResponseItem item, int level) {
    if (item.text != null) {
      div.write('<h${level + 2}>${item.text}</h${level + 2}>');
    }

    if (item.answer != null) {
      item.answer!.forEach((answer) {
        if (answer.valueString != null) {
          div.write('<p>${answer.valueString}</p>');
        } else if (answer.valueDecimal != null) {
          div.write('<p>${answer.valueDecimal.toString()}</p>');
        } else {
          print('Narrative generation not fully supported');
          div.write('<p>${answer.toString()}</p>');
        }
      });
    }

    if (item.item != null) {
      item.item!.forEach((nestedItem) {
        _addResponseItemToDiv(div, nestedItem, level + 1);
      });
    }
  }

  Narrative _generateNarrative(QuestionnaireResponse questionnaireResponse) {
    final div = StringBuffer('<div xmlns="http://www.w3.org/1999/xhtml">');
    questionnaireResponse.item!.forEach((item) {
      _addResponseItemToDiv(div, item, 0);
    });
    div.write('</div>');
    return new Narrative(
        div: div.toString(), status: NarrativeStatus.generated);
  }

  QuestionnaireResponse fhirQuestionnaireResponse(
      RPTaskResult result, QuestionnaireResponseStatus status) {
    final questionnaireResponse = QuestionnaireResponse(
      status: status,
      item: <QuestionnaireResponseItem>[],
      authored: FhirDateTime(DateTime.now()),
    );

    if (_questionnaire.item == null)
      return questionnaireResponse.copyWith(
          text: _generateNarrative(questionnaireResponse));

    _questionnaire.item!.forEach((item) {
      if (item.type == QuestionnaireItemType.group) {
        questionnaireResponse.item!.add(_fromGroupItem(item, result));
      } else {
        final responseItem = _fromQuestionItem(item, result);
        if (responseItem != null) questionnaireResponse.item!.add(responseItem);
      }
    });

    return questionnaireResponse.copyWith(
        text: _generateNarrative(questionnaireResponse));
  }

  RPCompletionStep completionStep() {
    return RPCompletionStep('completionID')
      ..title = 'Finished'
      ..text = 'Thank you for filling out the survey!';
  }
}
