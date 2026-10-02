"""Reviewed public API dispositions. Development-only; never consumer code.

Rules name native public member families; overload/default-argument differences
are adaptations, not signature equivalence. Unknown reference names fail closed.
The generated ledger freezes each full reference signature/declaration separately.
"""
import re

JAVA_OWNERS = {
    "ExpressionEvaluationException": "TranslationEvaluationError",
    "LocalizedString$Builder": "LocalizedString",
    "LocalizedString$ExpressionAlternative": "ExpressionAlternative",
    "LocalizedString$ExpressionTranslation": "ExpressionTranslation",
    "LocalizedString$LanguageFormTranslation": "LanguageFormTranslation",
    "LocalizedString$LanguageFormTranslationRange": "LanguageFormTranslationRange",
    "LocalizedString$PlaceholderDefinition": "PlaceholderDefinition",
    "LocalizedStringLoadingException": "LocalizedStringLoadingError",
    "LocalizedStringLoadingOptions$Builder": "LocalizedStringLoadingOptions",
    "LocalizedStringWarning$Type": "LocalizedStringWarning/WarningType",
    "MissingTranslationException": "MissingTranslationError",
    "PluralOperands$Builder": "PluralOperands", "Strings$Builder": "StringsConfiguration",
    "TranslationFallbackEvent$PrecedingFailure": "TranslationFallbackEvent/PrecedingFailure",
    "TranslationOptions$Builder": "TranslationOptions",
    "TranslationRuntimeLimits$Builder": "TranslationRuntimeLimits",
    "UnsupportedLocaleException": "UnsupportedLocaleError",
}
JAVA_TYPES = set("Animacy BidiIsolation Cardinality Classifier Clusivity Definiteness ExpressionEvaluationException Formality Gender GrammaticalCase LanguageForm LanguageRangeEquivalents LocaleMatchResult LocaleMatchType LocaleMatcher LocalizedString LocalizedString$Builder LocalizedString$ExpressionAlternative LocalizedString$ExpressionTranslation LocalizedString$LanguageFormTranslation LocalizedString$LanguageFormTranslationRange LocalizedString$PlaceholderDefinition LocalizedStringLoader LocalizedStringLoadingException LocalizedStringLoadingOptions LocalizedStringLoadingOptions$Builder LocalizedStringWarning LocalizedStringWarning$Type LocalizedStringWarningHandler MissingTranslationException Ordinality Phonetic PhoneticResolver PluralOperands PluralOperands$Builder Range Strings Strings$Builder TranslationFailure TranslationFailureHandler TranslationFailureReason TranslationFailureResponse TranslationFallbackEvent TranslationFallbackEvent$PrecedingFailure TranslationFallbackObserver TranslationFallbackPolicy TranslationOptions TranslationOptions$Builder TranslationResult TranslationResultStatus TranslationRuntimeLimits TranslationRuntimeLimits$Builder UnsupportedLocaleException".split())


def camel(name):
    parts = name.lower().split("_")
    return parts[0] + "".join(part.title() for part in parts[1:])


def result(disposition, owner=None, member=None, rationale=None, conforms=None):
    return {"disposition": disposition, "swiftOwner": owner, "swiftMemberFamily": member,
        "requiredConformance": conforms,
        "rationale": rationale or "Native Swift naming, argument labels, immutable values and default arguments adapt the reference API; public presence is checked separately from behavioral parity."}


def java(name, signature=None):
    name = name.removeprefix("com.lokalized.")
    if name not in JAVA_TYPES: raise ValueError(f"Unreviewed Java public type: {name}")
    owner = JAVA_OWNERS.get(name, name)
    if signature is None:
        return result("native-adaptation" if "$Builder" in name or name in JAVA_OWNERS else "implemented", owner,
            rationale="Swift configuration/initializers replace mutable builders; model/error names use the documented native mapping." if name in JAVA_OWNERS else None)
    if "(" not in signature:
        field = signature.rstrip(";").rsplit(" ", 1)[1].split(" = ", 1)[0]
        if "DEFAULT_EXHAUSTIVE_CLASSPATH_SEARCH" in signature:
            return result("platform-specific", rationale="Java classloader search policy has no Apple counterpart; Swift loads explicit local resources and bundles.")
        if name == "TranslationRuntimeLimits" and field.startswith("MAXIMUM_"):
            member = "hard" + camel(field)[0].upper() + camel(field)[1:]
        else:
            member = {"NONE": "disabled" if name == "BidiIsolation" else "noMatch",
                "IANA_REGISTRY": "ianaRegistry", "JDK": "jdk", "INVALID_CLASSPATH_LOCALE_FILENAME": "invalidLocaleFilename"}.get(field, camel(field))
        if name == "LocaleMatcher" and field == "MAXIMUM_LANGUAGE_RANGES": owner = "DefaultLocaleMatcher"
        return result("native-adaptation", owner, member)
    method = signature.split("(", 1)[0].rsplit(" ", 1)[1].rsplit(".", 1)[-1]
    if method in ("equals", "hashCode"):
        return result("native-adaptation", owner, conforms="Swift.Hashable",
            rationale="Swift Equatable/Hashable express exact value equality or documented callback identity; conditional generic conformances remain conditional.")
    if method == "toString":
        return result("native-adaptation", owner,
            rationale="Java diagnostic/debug rendering is not a public serialization format. Swift exposes structured fields and native descriptions where defined; Java toString text is not promised for every model.")
    if method in ("values", "valueOf"):
        return result("native-adaptation", owner, "init" if method == "valueOf" else None,
            conforms="Swift.RawRepresentable" if method == "valueOf" else "Swift.CaseIterable",
            rationale="RawRepresentable initialization and CaseIterable replace Java enum lookup/enumeration; native nil for an unknown raw value replaces Java valueOf throwing.")
    if method in ("loadFromClasspath", "loadFromClasspathResources", "isExhaustiveClasspathSearchEnabled", "exhaustiveClasspathSearch"):
        return result("platform-specific", "LocalizedStringLoader", "loadFromBundle" if "Classpath" in method and "Resources" not in method else "loadFromResources",
            rationale="Apple Bundle and explicit local resource maps replace JVM classloaders/JARs. Package-name search, archive discovery and exhaustive classpath traversal are not reproduced; 159 donor carrier cases remain pending.")
    if name == "LocalizedStringWarningHandler":
        return result("native-adaptation", owner,
            rationale="A synchronous throwing @Sendable closure replaces the functional interface: call it directly, supply a no-op to ignore, or throw an application-selected error. Factory methods are not duplicated.")
    if name == "PhoneticResolver": return result("native-adaptation", owner, rationale="A typed throwing @Sendable closure replaces the Java functional-interface resolve method; nil cannot inhabit its result.")
    if "$Builder" in name:
        if method in (name, name.split("$")[0] + "$Builder", "build"): return result("native-adaptation", owner, "init")
        # javap names nested constructors as Owner$Builder.
        if method.endswith("$Builder"): return result("native-adaptation", owner, "init")
        if owner == "PluralOperands": return result("native-adaptation", owner, "init", rationale="Visible places, compact exponent and runtime limits are parameters of immutable operand construction.")
        return result("native-adaptation", owner, "init", rationale=f"Builder {method} is a named parameter of native immutable {owner} construction; callbacks and optional inheritance keep their documented semantics.")
    if method in ("builder", "toBuilder", "defaults", "none"):
        return result("native-adaptation", owner, method if method in ("defaults", "none") else "init",
            rationale="Default values and immutable initializers replace Java builder/copy-builder mutation; rebuilding requires supplying retained fields explicitly.")
    if method in ("getResult", "getKeysForLocale", "getMissingKeys"):
        return result("implemented", owner, method)
    if method.startswith("get") and len(method) > 3:
        member = method[3].lower() + method[4:]
        if member == "supportedLocaleTags" and owner in ("Cardinality", "Ordinality"): member = "getSupportedLocaleTags"
        return result("native-adaptation", owner, member)
    if method in ("isMatch", "isFallback", "isInfinite"): return result("implemented", owner, method)
    aliases = {"loadFromFilesystem": "loadFromDirectory", "iterator": "makeIterator", "withFallbackLocale": "init"}
    if method == "withFallbackLocale": owner = "StringsConfiguration"
    if method in aliases: return result("native-adaptation", owner, aliases[method])
    if method == name or method == name.rsplit("$", 1)[-1] or method == name.replace("$", "."):
        return result("native-adaptation", owner, "init")
    allowed = {"forNumber", "forOperands", "forRange", "supportedCardinalitiesForLocale", "supportedOrdinalitiesForLocale",
        "exampleIntegerValuesForLocale", "exampleDecimalValuesForLocale", "matchFor", "bestMatchFor", "bestMatchForAcceptLanguage",
        "parseLanguageRanges", "parse", "ofInfiniteValues", "ofFiniteValues", "emptyFiniteRange", "emptyInfiniteRange", "get",
        "getResult", "getKeysForLocale", "getMissingKeys", "handle", "returnKey", "throwException", "returnString", "observe",
        "shouldTryNextLocale", "fallbackOnMissingTranslationOrNoMatchingAlternative", "fallbackOnAnyFailure", "neverFallback",
        "forLocale", "forLanguageRanges"}
    if method in allowed: return result("implemented", owner, method)
    raise ValueError(f"Unreviewed Java member: {name}: {signature}")


JS_TYPES = {name: name for name in "Animacy BidiIsolation Cardinality Classifier Clusivity Definiteness Formality Gender GrammaticalCase LanguageForm LocaleMatchResult LocaleMatchType LocalizedStringWarning LocalizedStringWarningHandler Ordinality Phonetic PhoneticResolver Strings TranslationFailure TranslationFailureHandler TranslationFailureReason TranslationFailureResponse TranslationFallbackPolicy TranslationOptions TranslationResult TranslationResultStatus CatalogIdentity LanguageFormAxis LanguageRange TranslationFallbackEvent TranslationFallbackObserver PlaceholderDefinition ParsedStringsFile CatalogIdentityInputV1 FetchEntry StringsManifestV1 LocaleMatcher".split()}
JS_TYPES.update({"CreateStringsOptions": "StringsConfiguration", "DirectCreateStringsOptions": "StringsConfiguration",
    "DirectLocaleContext": "TranslationOptions", "Definition": "LocalizedString", "TaggedLanguageFormValue": "LanguageFormValue",
    "Placeholders": "PlaceholderValues", "PrecedingFailure": "TranslationFallbackEvent/PrecedingFailure",
    "LocaleConfiguration": "ManifestLocaleConfiguration", "WeightedLanguageRange": "LanguageRange",
    "DirectLocaleMatcher": "DefaultLocaleMatcher", "LocalizedStringInput": "LocalizedString", "LocalizedStringNodeInput": "LocalizedString",
    "PlaceholderDefinitionInput": "PlaceholderDefinition", "WholeMessageAlternativeInput": "LocalizedString",
    "ParseStringsOptions": "LocalizedStringLoadingOptions", "ParsedCatalogLimits": "LocalizedStringLoadingOptions",
    "StringsLoadingLimits": "LocalizedStringLoadingOptions", "BuiltinTranslationFallbackPolicy": "TranslationFallbackPolicy",
    "LanguageFormName": "LanguageFormValue", "LokalizedErrorCode": "TranslationEvaluationError",
    "DataProvenance": "BuildMetadata", "SourceDataProvenance": "BuildMetadata"})
JS_EXCLUDED = {
    "DigestUnavailableError": "WebCrypto capability detection is browser-specific; Apple SDK CryptoKit supplies pure identity hashing at the declared floors.",
    "loadStrings": "JS browser HTTP acquisition; applications own Swift remote acquisition.",
    "loadEntireManifest": "JS browser HTTP acquisition; no Swift asynchronous manifest-delivery API.",
    "LoadFailure": "JS manifest-delivery stages and partial-network diagnostics are outside Swift scope.",
    "LoadStringsOptions": "JS request/transport/signal options are outside Swift scope.",
    "LoadedStrings": "JS verified delivery result/coverage is outside Swift runtime scope.",
    "PartialFailurePolicy": "JS network-load policy is outside Swift scope; native local loads throw on failure.",
    "StringsLoadCoverage": "JS manifest-delivery coverage is outside Swift scope.",
    "StringsLoadVerification": "JS verified-delivery runtime provenance is outside Swift scope.",
    "LoadedCreateStringsOptions": "JS verified loaded-result construction branch is outside Swift scope; use direct native configuration.",
    "createSsrStamp": "JS SSR/hydration delivery API has no native Swift consumer.",
    "validateSsrStamp": "JS SSR/hydration delivery API has no native Swift consumer.",
    "LokalizedSsrStampV1": "JS-only producer identity and SSR handoff protocol.",
    "SsrLocaleContext": "JS SSR handoff shape is outside Swift scope.",
    "SsrLocaleMatchV1": "JS SSR handoff shape is outside Swift scope.",
    "createStringsManifestFromDirectory": "JS publishing tooling; no Swift release requirement for directory-to-manifest publication.",
    "DirectoryManifestOptions": "JS publishing tool options; no native runtime publishing workflow.",
    "loadEntireManifestFromFiles": "JS file-manifest/verified-result adapter; native Swift follows Java local loading and has no manifest-delivery pipeline.",
    "loadStringsFromFiles": "JS file-manifest/verified-result adapter; native Swift follows Java local loading and has no manifest-delivery pipeline.",
    "LoadStringsFromFilesOptions": "JS manifest-delivery adapter options are outside native Swift scope.",
    "OrdinalData": "JS optional data-delivery handle; complete ordinal data is always built into Swift.",
    "CardinalRangeData": "JS optional data-delivery handle; complete range data is always built into Swift.",
    "PluralDataRuntime": "JS injected data runtime is an internal delivery representation; native public plural services use the complete pinned built-in data.",
    "ordinalData": "JS optional data module handle; native ordinal services include built-in data without imports.",
    "cardinalRangeData": "JS optional data module handle; native range services include built-in data without imports.",
    "LokalizedError": "JS shared Error base/class code inheritance; Swift uses typed native Error values and retained causes.",
    "ResolutionError": "JS internal fragment-resolution error carrier; Swift exposes TranslationEvaluationError and structured failure reasons/causes.",
}
JS_FUNCTIONS = {
    "cardinalityForNumber": ("Cardinality", "forNumber"), "cardinalityForOperands": ("Cardinality", "forOperands"),
    "cardinalityForRange": ("Cardinality", "forRange"), "ordinalityForNumber": ("Ordinality", "forNumber"),
    "ordinalityForOperands": ("Ordinality", "forOperands"),
    "getSupportedCardinalityLocaleTags": ("Cardinality", "getSupportedLocaleTags"),
    "getSupportedOrdinalityLocaleTags": ("Ordinality", "getSupportedLocaleTags"),
    "supportedCardinalitiesForLocale": ("Cardinality", "supportedCardinalitiesForLocale"),
    "supportedOrdinalitiesForLocale": ("Ordinality", "supportedOrdinalitiesForLocale"),
    "decimal": ("ExactDecimal", "init"), "pluralOperands": ("PluralOperands", "forNumber"),
    "chooseBrowserLocale": ("PreferredLanguageChooser", "chooseAppleLocale"),
    "chooseLocaleForPreferredLanguages": ("PreferredLanguageChooser", "chooseLocaleForPreferredLanguages"),
    "createStrings": ("DefaultStrings", "init"), "createLocaleMatcher": ("DefaultLocaleMatcher", "init"),
    "forLocale": ("TranslationOptions", "forLocale"), "forLocaleMatch": ("TranslationOptions", "forLocaleMatch"),
    "forLanguageRanges": ("TranslationOptions", "forLanguageRanges"), "forAcceptLanguage": ("TranslationOptions", "forAcceptLanguage"),
    "returnString": ("TranslationFailureResponse", "returnString"),
    "parseLanguageRanges": ("LanguageRange", "parse"), "parseStrings": ("LocalizedStringLoader", "parse"),
    "defineCatalog": ("LocalizedStringLoader", "defineCatalog"), "defineLocalizedString": ("LocalizedString", "init"),
    "mergeParsedStringsFiles": ("LocalizedStringLoader", "mergeParsedStringsFiles"),
    "chain": ("LocalizedStringLoader", "chain"), "computeCatalogIdentity": ("LocalizedStringLoader", "computeCatalogIdentity"),
    "fetchSet": ("LocalizedStringLoader", "fetchSet"), "localeConfigurationForManifest": ("LocalizedStringLoader", "localeConfigurationForManifest"),
    "parseStringsManifest": ("LocalizedStringLoader", "parseStringsManifest"), "validateStringsManifest": ("LocalizedStringLoader", "validateStringsManifest"),
    "loadStringsFromDirectory": ("LocalizedStringLoader", "loadFromDirectory"),
    "readStringsFromDirectory": ("LocalizedStringLoader", "loadFromDirectory"),
    "readStringsManifest": ("LocalizedStringLoader", "parseStringsManifest"),
}


def javascript(name):
    if name in JS_EXCLUDED: return result("platform-specific", rationale=JS_EXCLUDED[name])
    if name in JS_TYPES:
        return result("native-adaptation", JS_TYPES[name], rationale="Native typed catalog/configuration/value representation replaces JS object/type aliases; direct construction is retained while the verified browser-delivery branch is outside scope.")
    if name.endswith("FormName") and name.removesuffix("FormName") in JS_TYPES:
        return result("native-adaptation", name.removesuffix("FormName"), conforms="Swift.RawRepresentable")
    if name in JS_FUNCTIONS:
        owner, member = JS_FUNCTIONS[name]
        rationale = None
        if name in ("readStringsManifest", "readStringsFromDirectory", "loadStringsFromDirectory"):
            rationale = "Native local parse/directory APIs return parsed catalogs, as in Java. Application file acquisition composes with the pure manifest parser; no JS verified-loaded record is manufactured."
        if name == "chooseBrowserLocale": rationale = "Apple preferredLanguages acquisition replaces navigator.languages, using the same ordered chooser kernel."
        return result("native-adaptation", owner, member, rationale)
    if name in ("ConfigurationError", "MissingTranslationError", "UnsupportedLocaleError", "StringsParseError", "LocalizedStringLoadingError"):
        return result("native-adaptation", name)
    if name == "ExpressionEvaluationError": return result("native-adaptation", "TranslationEvaluationError")
    if name in ("RETURN_KEY", "THROW_EXCEPTION"):
        return result("native-adaptation", "TranslationFailureResponse", "returnKey" if name == "RETURN_KEY" else "throwException")
    if name in ("behavioralVectorsVersion", "cardinalityMode", "cldrVersion", "dataFingerprint", "ianaDataFingerprint", "ianaRegistryDate", "localeDataMode"):
        return result("native-adaptation", "BuildMetadata", name)
    if name == "LoadStringsFromDirectoryOptions": return result("native-adaptation", "LocalizedStringLoadingOptions", rationale="Native directory limits and warning callback parameters adapt the local subset; JS verified-loaded/manifest options are outside scope.")
    for prefix, owner in {"ANIMACY": "Animacy", "CARDINALITY": "Cardinality", "CASE": "GrammaticalCase",
        "CLASSIFIER": "Classifier", "CLUSIVITY": "Clusivity", "DEFINITENESS": "Definiteness", "FORMALITY": "Formality",
        "GENDER": "Gender", "ORDINALITY": "Ordinality", "PHONETIC": "Phonetic"}.items():
        if name.startswith(prefix + "_"): return result("native-adaptation", owner, camel(name[len(prefix) + 1:]))
    raise ValueError(f"Unreviewed JS export/declaration: {name}")
