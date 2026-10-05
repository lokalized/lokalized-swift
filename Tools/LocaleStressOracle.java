package com.lokalized;

import com.lokalized.MinimalJson.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;

/** Development-only locale-input probe compiled with pinned Java 3.1.0 sources. */
public final class LocaleStressOracle {
  private static JsonArray units(String text) {
    JsonArray result = Json.array();
    for (int index = 0; index < text.length(); index++) result.add((int) text.charAt(index));
    return result;
  }

  private static boolean syntax(String tag) {
    try { new Locale.Builder().setLanguageTag(tag); return true; }
    catch (RuntimeException failure) { return false; }
  }

  private static boolean rebuildable(Locale locale) {
    try { LocaleUtils.requireWellFormed(locale, "Locale"); return true; }
    catch (RuntimeException failure) { return false; }
  }

  private static boolean catalog(String tag) {
    if (!tag.matches("[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*")) return false;
    Locale locale;
    try { locale = new Locale.Builder().setLanguageTag(tag).build(); }
    catch (RuntimeException failure) { return false; }
    String lower = tag.toLowerCase(Locale.ROOT);
    if (lower.startsWith("x-")) return true;
    boolean explicit = lower.equals("und") || lower.startsWith("und-");
    return (!locale.getLanguage().isEmpty() || explicit) && CldrLocaleData.isKnownLanguageTag(tag);
  }

  private static JsonArray observe(String text) {
    Locale locale = Locale.forLanguageTag(text);
    StringBuilder extensions = new StringBuilder();
    for (char key : locale.getExtensionKeys()) {
      if (extensions.length() > 0) extensions.append('-');
      extensions.append(key).append('-').append(locale.getExtension(key));
    }
    StringBuilder fallback = new StringBuilder();
    for (Locale candidate : CldrLocaleData.fallbackLocalesFor(locale)) {
      if (fallback.length() > 0) fallback.append('|');
      fallback.append(candidate.toLanguageTag());
    }
    String script = locale.getScript();
    if (script.isEmpty()) {
      Optional<String> likely = CldrLocaleData.likelySubtagFor(locale);
      if (likely.isPresent()) script = Locale.forLanguageTag(likely.get()).getScript();
    }
    boolean full = syntax(text), rebuilt = rebuildable(locale);
    String[] fields = {locale.toLanguageTag(), locale.getLanguage(), locale.getScript(), locale.getCountry(),
        locale.getVariant(), extensions.toString(), locale.toString(), "" + rebuilt, "" + full, "" + (full && rebuilt),
        "" + catalog(text), CldrLocaleData.canonicalLanguageTag(text),
        CldrLocaleData.canonicalLanguageTag(locale.toLanguageTag()), CldrLocaleData.likelySubtagFor(text).orElse("<nil>"),
        CldrLocaleData.likelySubtagFor(locale).orElse("<nil>"),
        CldrLocaleData.languageScriptForLikelySubtag(text).orElse("<nil>"), fallback.toString(),
        "" + CldrLocaleData.isKnownLanguageTag(text), "" + CldrLocaleData.hasUndeterminedLanguage(text),
        "" + CldrLocaleData.isPrivateUseLanguageTag(text), "" + CldrLocaleData.isRightToLeftScript(script)};
    JsonArray values = Json.array();
    for (String field : fields) values.add(units(field));
    return values;
  }

  public static void main(String[] args) throws Exception {
    BufferedReader input = new BufferedReader(new InputStreamReader(System.in, StandardCharsets.US_ASCII));
    String line;
    while ((line = input.readLine()) != null) {
      String[] fields = line.split("\t", -1);
      if (fields.length != 2) throw new IllegalArgumentException("expected two input fields");
      String text = new String(Base64.getDecoder().decode(fields[1]), StandardCharsets.UTF_8);
      System.out.println(Json.object().add("id", fields[0]).add("values", observe(text)));
    }
  }
}
