# Local catalog consumers

Start with the [runnable usage guide](../Documentation/USAGE.md) for complete
package/resource setup and translation examples. The
[development guide](../Documentation/DEVELOPMENT.md) explains how its Markdown
programs and the consumers below are compiled and qualified.

`SwiftPMCatalogConsumer` is an executable package with a local dependency on this repository. Run `swift run` in its directory to check real `.copy("Lokalized")` resources and `Bundle.module` loading.

Open `AppleLocalCatalogs/AppleLocalCatalogs.xcodeproj` and select `MacCatalogs` or `IOSCatalogs` to build the SwiftUI app. Both targets use the same source and `SharedCatalogs/Lokalized` folder reference. The app shows concurrent English/French contexts and an explicit Apple preferred-language selection. Catalogs are loaded once; translation errors have an explicit display policy.

From the repository root, `python3 Tools/verify_local_delivery.py` compiles both consumer language modes, builds all three Apple products, verifies their resources/deployment floors and executes the packaged macOS application. See [Apple local delivery](../Documentation/APPLE-LOCAL-DELIVERY.md) for packaging and qualification details.

The SwiftPM catalog consumer also computes system SHA-256 digests of its actual bundled files, builds a manifest claim and qualifies its `fr-CA` fetch plan against ordinary `file:` resource URLs. This exercises identity/validation/planning only; it does not present those plans as verified loaded records.
