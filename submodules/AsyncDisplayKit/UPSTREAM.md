# AsyncDisplayKit

Vendored from https://github.com/TextureGroup/Texture.git at commit `d8aa8c796dd7770ea177989253ef1cf8878cd50a`.
The upstream podspec identifies this source as Texture 3.2.0.

Source contains the `Texture/Core` files selected by `Texture.podspec`
(`Source/**/*.h` and `Source/**/*.mm`), with the original directory structure
and file contents preserved. LICENSE is the upstream Apache 2.0 license.
This is a local copy, not a Git submodule; changes are maintained in Contact.

The Bazel target `//submodules/AsyncDisplayKit` exports the `AsyncDisplayKit`
module. Its public headers follow the Core subspec. Flattened include paths
are generated during the build to support upstream's
`<AsyncDisplayKit/Header.h>` imports without duplicating maintained sources.

PINRemoteImage, IGListKit and Yoga are not dependencies. Video, MapKit,
Photos and AssetsLibrary integrations are disabled. Their guarded source
files remain because they belong to the upstream Core file selection.
The default TextNode implementation remains enabled.
