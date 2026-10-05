package com.lokalized;

import com.lokalized.MinimalJson.*;
import java.io.*;
import java.math.*;
import java.nio.charset.StandardCharsets;
import java.util.*;

/** Development-only expression probe compiled with the pinned Java sources. */
public final class ExpressionStressOracle {
  private static JsonArray units(String text) {
    JsonArray result = Json.array();
    for (int index = 0; index < text.length(); index++) result.add((int) text.charAt(index));
    return result;
  }

  private static JsonArray error(Throwable failure) {
    JsonArray chain = Json.array();
    for (Throwable current = failure; current != null; current = current.getCause()) {
      chain.add(Json.array().add(current.getClass().getName())
          .add(current.getMessage() == null ? Json.NULL : units(current.getMessage())));
      if (chain.size() > 8) throw new IllegalStateException("unbounded error cause chain");
    }
    return chain;
  }

  private static Object value(JsonArray encoded) {
    String kind = encoded.get(0).asString();
    if (kind.equals("null")) return null;
    if (kind.equals("boolean")) return Boolean.valueOf(encoded.get(1).asString());
    String raw = encoded.get(1).asString();
    switch (kind) {
      case "text": return raw;
      case "byte": return Byte.valueOf(raw);
      case "short": return Short.valueOf(raw);
      case "integer": return Integer.valueOf(raw);
      case "long": return Long.valueOf(raw);
      case "bigInteger": return new BigInteger(raw);
      case "decimal": return new BigDecimal(raw);
      case "floatBits": return Float.intBitsToFloat((int) Long.parseUnsignedLong(raw, 16));
      case "doubleBits": return Double.longBitsToDouble(Long.parseUnsignedLong(raw, 16));
      case "form":
        String[] parts = raw.split("_", 2);
        if (parts.length != 2) throw new IllegalArgumentException("invalid form fixture");
        switch (parts[0]) {
          case "CARDINALITY": return Cardinality.valueOf(parts[1]);
          case "ORDINALITY": return Ordinality.valueOf(parts[1]);
          case "GENDER": return Gender.valueOf(parts[1]);
          case "CASE": return GrammaticalCase.valueOf(parts[1]);
          case "DEFINITENESS": return Definiteness.valueOf(parts[1]);
          case "CLASSIFIER": return Classifier.valueOf(parts[1]);
          case "FORMALITY": return Formality.valueOf(parts[1]);
          case "CLUSIVITY": return Clusivity.valueOf(parts[1]);
          case "ANIMACY": return Animacy.valueOf(parts[1]);
          case "PHONETIC": return Phonetic.valueOf(parts[1]);
          default: throw new IllegalArgumentException("invalid form axis fixture");
        }
      default: throw new IllegalArgumentException("unknown value fixture: " + kind);
    }
  }

  private static Map<String, Object> context(JsonObject encoded) {
    Map<String, Object> result = new HashMap<>();
    for (JsonObject.Member member : encoded) result.put(member.getName(), value(member.getValue().asArray()));
    return result;
  }

  public static void main(String[] args) throws Exception {
    BufferedReader input = new BufferedReader(new InputStreamReader(System.in, StandardCharsets.UTF_8));
    String line;
    while ((line = input.readLine()) != null) {
      String[] fields = line.split("\t", -1);
      if (fields.length != 6) throw new IllegalArgumentException("expected six fields");
      String source = new String(Base64.getDecoder().decode(fields[3]), StandardCharsets.UTF_8);
      JsonArray contexts = Json.parse(new String(Base64.getDecoder().decode(fields[4]), StandardCharsets.UTF_8)).asArray();
      TranslationRuntimeLimits.Builder builder = TranslationRuntimeLimits.builder();
      if (!fields[2].isEmpty()) for (String option : fields[2].split(",")) {
        String[] pair = option.split("=", -1);
        int limit = Integer.parseInt(pair[1]);
        switch (pair[0]) {
          case "characters": builder.maximumExpressionCharacters(limit); break;
          case "tokens": builder.maximumExpressionTokens(limit); break;
          case "nesting": builder.maximumExpressionNestingDepth(limit); break;
          case "precision": builder.maximumNumberPrecision(limit); break;
          case "scale": builder.maximumAbsoluteNumberScale(limit); break;
          case "phonetic": builder.maximumInterpolatedOutputCharacters(limit); break;
          default: throw new IllegalArgumentException("unknown limit fixture");
        }
      }
      TranslationRuntimeLimits limits = builder.build();
      JsonObject row = Json.object().add("id", fields[0]);
      JsonArray results = Json.array();
      ExpressionEvaluator evaluator = new ExpressionEvaluator(null, null, limits);
      try {
        ExpressionEvaluator.CompiledExpression compiled = evaluator.compile(source);
        row.add("compile", Json.NULL);
        for (JsonValue item : contexts) {
          JsonObject result = Json.object();
          JsonArray calls = Json.array();
          // Capture calls per evaluation, so skipped branches and IR reuse are visible.
          final JsonArray invocationCalls = calls;
          PhoneticResolver scenarioResolver = (term, locale) -> {
            invocationCalls.add(Json.array().add(units(term)).add(units(locale.toLanguageTag())));
            if (fields[5].equals("throw")) throw new IllegalStateException("resolver failure");
            return term.startsWith("hon") ? Phonetic.VOWEL : Phonetic.CONSONANT;
          };
          ExpressionEvaluator scenario = new ExpressionEvaluator(null, scenarioResolver, limits);
          try { result.add("value", scenario.evaluateCompiledExpression(compiled, context(item.asObject()), Locale.forLanguageTag(fields[1]))); }
          catch (Exception failure) { result.add("error", error(failure)); }
          result.add("calls", calls);
          results.add(result);
        }
      } catch (Exception failure) { row.add("compile", error(failure)); }
      row.add("results", results);
      System.out.println(row);
    }
  }
}
