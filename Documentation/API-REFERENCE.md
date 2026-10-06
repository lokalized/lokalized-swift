# Building and publishing the Swift API reference

The Swift reference uses the selected Xcode's Swift symbol-graph extractor and
DocC compiler. It needs no package plugin or external dependency. The catalog
at `Sources/Lokalized/Lokalized.docc` also works with Xcode's **Product > Build
Documentation** command.

## Development reference

From the repository root on macOS, with Xcode selected and Swift 6.2 or later:

```sh
python3 Tools/test_api_documentation.py
python3 Tools/build_api_documentation.py
```

Serve `.build/api-documentation/site` with a static file server and open its
`index.html`. The reference entry is
`development/documentation/lokalized/`. DocC emits static routes, so ordinary
directory-index hosting suffices; no SPA rewrite is required. Retain the complete
edition directory, including its data, navigation index, JavaScript, and CSS.

Only the public `Lokalized` module is published. The conformance executable and
support module are excluded. The generator compiles only the library target and
emits its public symbol graphs during compilation, avoiding Swift 6.2's
package-wide export of unbuilt generated test modules. Each reference build uses
fresh build and graph directories so it cannot publish stale symbols.
All authored public declarations, including methods, properties, initializers,
and enum cases, must have source documentation. Known internal maintenance
markers and unresolved DocC links fail generation. `coverage.json` reports
authored API coverage separately from compiler-generated and inherited members,
whose availability depends on the selected compiler. Complete signatures do not
imply complete prose coverage. `reference-build.json` records the compiler, source revision, dirty
state, input fingerprint, and coverage totals.

Development documentation is explicitly labeled as unreleased source. Source
links are emitted only for clean checkouts, so locally modified source is never
attributed to an older GitHub revision. Generated files remain under ignored
`.build/`. Consumer builds still have zero external dependencies.

## Release references

From a clean checkout whose HEAD already has the intended semantic-version tag,
run `python3 Tools/build_api_documentation.py --release VERSION`, replacing
`VERSION` with that version. Tags may be `VERSION` or `vVERSION`. The generator
refuses dirty source or a missing matching tag. It does not create tags, commits,
GitHub releases, or package publications.

To correct documentation for an existing release without changing its code, use:

```sh
python3 Tools/build_api_documentation.py --release 1.0.0 \
  --correction-reason "Improve consumer API documentation"
```

This explicit mode compares library Swift tokens, the source file inventory,
package configuration, resources, and public declarations with the release tag.
It uses SwiftParser and SwiftSyntax bundled with the selected Xcode only during
verification; they are not package or runtime dependencies. Changes to code or
public declarations are rejected. Prose can change in a locally modified tree,
and the build metadata records the release revision, correction reason, and
actual source fingerprint. The tag and published package remain unchanged.

Release output lives at `VERSION/documentation/lokalized/`. DocC's hosting base
path includes the edition, so assets and navigation remain inside that version.
The generated root index lists existing editions without removing their files.

## Hosting at swiftdoc.lokalized.com

The `Swift API documentation` workflow builds with Xcode 26.0.1 / Swift 6.2 on
the Intel macOS runner. It builds development references for ordinary pushes
and pull requests, and versioned references for version-tag pushes. Download
the `swift-api-reference` artifact, unzip it, then extract the enclosed archive:

```sh
tar -xzf swift-api-reference.tar.gz
```

This produces the complete static `site/` directory. DocC uses Swift argument
labels and operators in filenames, such as `!=(_:_:).json`; GitHub's artifact
uploader rejects those names when files are uploaded individually. The tarball
preserves the original filenames and links while omitting macOS file metadata.
Extract on macOS or Linux before copying the site's contents into the hosting
repository's `dist/` directory.
The workflow has only read permissions and does not deploy.

Publish those contents to a static host with the custom domain
`swiftdoc.lokalized.com`, configure DNS as instructed by the host, and enable
HTTPS. A Linux static host can serve the generated output; the DocC build itself
runs on macOS with Xcode. No Swift runtime runs on the documentation host.

When updating an existing site, retain prior release directories. Restore them
into the local `site/` output before rebuilding to regenerate the edition index,
or merge the newly built edition into the hosting site's existing tree and
update its root index. A fresh CI artifact contains only the edition built by
that run, so replacing the entire deployed tree would remove older references.

Before enabling the main website's API link, verify the root, a type page loaded
directly by URL, a method page, and search. The website label is **SwiftDoc**;
DocC supplies the native reference UI.
