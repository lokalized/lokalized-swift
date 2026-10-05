package com.lokalized;

import com.lokalized.LocalizedString.*;
import com.lokalized.MinimalJson.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;

/** Development-only byte-door probe. The runner compiles this with fresh pinned library sources. */
public final class ParserStressOracle {
  public static void main(String[] args) throws Exception {
    BufferedReader input = new BufferedReader(new InputStreamReader(System.in, StandardCharsets.UTF_8));
    String line;
    while ((line = input.readLine()) != null) {
      String[] fields = line.split("\t", -1);
      if (fields.length != 4) throw new IllegalArgumentException("expected four input fields");
      LocalizedStringLoadingOptions.Builder options = LocalizedStringLoadingOptions.builder();
      for (String field : fields[2].split(",")) {
        if (field.isEmpty()) continue;
        String[] pair = field.split("=", -1);
        int value = Integer.parseInt(pair[1]);
        switch (pair[0]) {
          case "maximumInputBytes": options.maximumInputBytes(value); break;
          case "maximumTotalInputBytes": options.maximumTotalInputBytes((long) value); break;
          case "maximumReaderCharacters": options.maximumReaderCharacters(value); break;
          case "maximumJsonNestingDepth": options.maximumJsonNestingDepth(value); break;
          case "maximumTranslationNodes": options.maximumTranslationNodes(value); break;
          case "maximumWarnings": options.maximumWarnings(value); break;
          default: throw new IllegalArgumentException("unknown option " + pair[0]);
        }
      }
      // Constructing invalid options is a harness error, not a catalog-parser observation.
      LocalizedStringLoadingOptions limits = options.build();
      JsonArray warnings = Json.array();
      JsonObject row = Json.object().add("id", fields[0]);
      try {
        Set<LocalizedString> parsed = LocalizedStringLoader.parse(
            new ByteArrayInputStream(Base64.getDecoder().decode(fields[3])),
            Locale.forLanguageTag(fields[1]), fields[0],
            warning -> warnings.add(units(warning.getMessage())), limits);
        List<LocalizedString> roots = new ArrayList<>(parsed);
        roots.sort(Comparator.comparing(LocalizedString::getKey));
        JsonArray contents = Json.array();
        for (LocalizedString root : roots) contents.add(node(root));
        row.add("status", "returned").add("class", Json.NULL).add("value", contents);
      } catch (Exception error) {
        row.add("status", "threw").add("class", error.getClass().getName())
            .add("value", units(error.getMessage()));
      }
      System.out.println(row.add("warnings", warnings));
    }
  }

  // Integer UTF-16 units avoid normalization and UTF-8 replacement by an output stream.
  private static JsonValue units(String text) {
    if (text == null) return Json.NULL;
    JsonArray result = Json.array();
    for (int index = 0; index < text.length(); index++) result.add((int) text.charAt(index));
    return result;
  }

  private static JsonArray node(LocalizedString node) {
    JsonArray placeholders = Json.array();
    for (Map.Entry<String, PlaceholderDefinition> entry : node.getPlaceholderDefinitions().entrySet())
      placeholders.add(Json.array().add(units(entry.getKey())).add(placeholder(entry.getValue())));
    JsonArray alternatives = Json.array();
    for (LocalizedString alternative : node.getAlternatives()) alternatives.add(node(alternative));
    return Json.array().add(units(node.getKey())).add(units(node.getTranslation().orElse(null)))
        .add(units(node.getCommentary().orElse(null))).add(placeholders).add(alternatives);
  }

  private static JsonArray placeholder(PlaceholderDefinition definition) {
    if (definition instanceof LanguageFormTranslation) {
      LanguageFormTranslation form = (LanguageFormTranslation) definition;
      JsonValue range = Json.NULL;
      if (form.getRange().isPresent()) {
        LanguageFormTranslationRange r = form.getRange().get();
        range = Json.array().add(units(r.getStart())).add(units(r.getEnd()));
      }
      SortedMap<String, String> translations = new TreeMap<>();
      for (Map.Entry<LanguageForm, String> entry : form.getTranslationsByLanguageForm().entrySet()) {
        String name = FORM_NAMES.get(entry.getKey());
        if (name == null) throw new IllegalStateException("unmapped language form");
        translations.put(name, entry.getValue());
      }
      JsonArray contents = Json.array();
      for (Map.Entry<String, String> entry : translations.entrySet())
        contents.add(Json.array().add(units(entry.getKey())).add(units(entry.getValue())));
      return Json.array().add("languageForm").add(units(form.getValue().orElse(null))).add(range).add(contents);
    }
    if (definition instanceof ExpressionTranslation) {
      ExpressionTranslation template = (ExpressionTranslation) definition;
      JsonArray alternatives = Json.array();
      for (ExpressionAlternative alternative : template.getAlternatives())
        alternatives.add(Json.array().add(units(alternative.getExpression())).add(units(alternative.getTranslation())));
      return Json.array().add("expression").add(units(template.getTranslation())).add(alternatives);
    }
    throw new IllegalStateException("unhandled placeholder type");
  }

  private static final Map<LanguageForm, String> FORM_NAMES = formNames();
  private static Map<LanguageForm, String> formNames() {
    Map<LanguageForm, String> names = new HashMap<>();
    for (Gender f : Gender.values()) names.put(f, LocalizedStringUtils.localizedStringNameForGenderName(f.name()));
    for (GrammaticalCase f : GrammaticalCase.values()) names.put(f, LocalizedStringUtils.localizedStringNameForGrammaticalCaseName(f.name()));
    for (Definiteness f : Definiteness.values()) names.put(f, LocalizedStringUtils.localizedStringNameForDefinitenessName(f.name()));
    for (Classifier f : Classifier.values()) names.put(f, LocalizedStringUtils.localizedStringNameForClassifierName(f.name()));
    for (Formality f : Formality.values()) names.put(f, LocalizedStringUtils.localizedStringNameForFormalityName(f.name()));
    for (Clusivity f : Clusivity.values()) names.put(f, LocalizedStringUtils.localizedStringNameForClusivityName(f.name()));
    for (Animacy f : Animacy.values()) names.put(f, LocalizedStringUtils.localizedStringNameForAnimacyName(f.name()));
    for (Cardinality f : Cardinality.values()) names.put(f, LocalizedStringUtils.localizedStringNameForCardinalityName(f.name()));
    for (Ordinality f : Ordinality.values()) names.put(f, LocalizedStringUtils.localizedStringNameForOrdinalityName(f.name()));
    for (Phonetic f : Phonetic.values()) names.put(f, LocalizedStringUtils.localizedStringNameForPhoneticName(f.name()));
    return names;
  }
}
