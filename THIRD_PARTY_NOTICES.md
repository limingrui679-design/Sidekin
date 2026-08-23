# Third-party notices

Sidekin's proprietary license applies only to Sidekin-authored code, text, and
visual assets. Third-party software keeps its own license. The lockfile pins the
exact dependency versions used by this source Beta.

Runtime components include:

| Component | Version | License and notice location |
|---|---:|---|
| Electron | 43.4.0 | MIT; Electron and Chromium license files are included in the packaged runtime. |
| adm-zip | 0.6.0 | MIT; the package includes its `LICENSE` file. |
| sharp | 0.35.3 | Apache-2.0; the package includes its `LICENSE` file. |
| prebuilt libvips used by sharp | 1.3.2 platform package | LGPL-3.0-or-later; the platform package's included `README.md` lists libvips and bundled-library licenses and source locations. |

Development-only tools and their transitive dependencies are not product code;
their declared licenses remain available in their installed package metadata.
This notice does not replace or modify any third-party license.
