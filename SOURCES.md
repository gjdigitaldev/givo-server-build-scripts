# Sources

Every archive the scripts here download, and every prebuilt file we ship unchanged, with its SHA-256. A script stops when a file does not match.

## Comskip (all platforms)

| What | Version | Address | SHA-256 |
| --- | --- | --- | --- |
| Comskip source | git commit a140b6ac8bc8f596729e9052819affc779c3b377 | https://github.com/erikkaashoek/Comskip | (git commit) |
| FFmpeg 7.1.1 (decode-only, inside comskip) | 7.1.1 | https://ffmpeg.org/releases/ffmpeg-7.1.1.tar.xz | `733984395e0dbbe5c046abda2dc49a5544e7e0e1e2366bba849222ae9e3a03b1` |
| argtable 2.13 | 2.13 | https://downloads.sourceforge.net/project/argtable/argtable/argtable-2.13/argtable2-13.tar.gz | `8f77e8a7ced5301af6e22f47302fdbc3b1ff41f2b83c43c77ae5ca041771ddbf` |
| zlib 1.3.2 (Windows builds) | 1.3.2 | https://github.com/madler/zlib/releases/download/v1.3.2/zlib-1.3.2.tar.gz | `bb329a0a2cd0274d05519d61c667c062e06990d72e125ee2dfa8de64f0119d16` |

## whisper.cpp (whisper-cli)

| What | Version | Address | SHA-256 |
| --- | --- | --- | --- |
| whisper.cpp source (macOS, Linux, Windows x64 and ARM64) | v1.9.1 = git commit f049fff95a089aa9969deb009cdd4892b3e74916 | https://github.com/ggml-org/whisper.cpp/tree/v1.9.1 | (git commit) |

## FFmpeg for Windows (BtbN builds, shipped unchanged)

| What | Version | Address | SHA-256 |
| --- | --- | --- | --- |
| Windows x64 | N-125365-g9a01c1cb6a | https://github.com/BtbN/FFmpeg-Builds/releases/download/autobuild-2026-06-30-13-34/ffmpeg-N-125365-g9a01c1cb6a-win64-gpl.zip | `52c0383c460f0ec1039088f1591921fb82e3b870b32aab8faf2ff1e5ae14bf9d` |
| Windows ARM64 | N-125365-g9a01c1cb6a | https://github.com/BtbN/FFmpeg-Builds/releases/download/autobuild-2026-06-30-13-34/ffmpeg-N-125365-g9a01c1cb6a-winarm64-gpl.zip | `f1e59d579755fbb5ecfe9cde2ec2c4a59a71ae701fa8d770c95b4db9dabcedf2` |
| their source: FFmpeg at that commit | 9a01c1cb6a | https://github.com/FFmpeg/FFmpeg/tree/9a01c1cb6a | (git commit) |
| their build scripts | autobuild-2026-06-30-13-34 | https://github.com/BtbN/FFmpeg-Builds/releases/tag/autobuild-2026-06-30-13-34 | (git tag) |

## Toolchains and base images

| What | Version | Address | SHA-256 |
| --- | --- | --- | --- |
| llvm-mingw (Windows cross-compiler, macOS) | 20261006 UCRT | https://github.com/mstorsjo/llvm-mingw/releases/download/20261006/llvm-mingw-20261006-ucrt-macos-universal.tar.xz | `a7a19b11048e89372637d26279cdb7c430ed3cf8c1e224310421312bf986ebf6` |
| Martin Riedl's FFmpeg build script (macOS FFmpeg) | git commit 05581a45b70c22f8b03a3ce51c577fb6ccc64d56 | https://git.martin-riedl.de/ffmpeg/build-script | (git commit) |
| Docker base image: tools stage | debian:bookworm | docker.io/library/debian:bookworm | sha256:268fb24c39bca92d326dd83ea3abebe4a3f7751c804ffef23bb6d857dd343ff8 (index digest) |

## FFmpeg for macOS (`ffmpeg/macos-sources.tsv`)

Served to Martin Riedl's script by `ffmpeg/curl-shim.sh`; nothing else is downloaded. "tofu" means trust on first use: the archive was recorded the first time we fetched it (upstream publishes no checksum for most of them).

| Archive | Bytes | SHA-256 | First fetched (UTC) | Provenance |
| --- | --- | --- | --- | --- |
| http://www.nasm.us/pub/nasm/releasebuilds/2.16.03/nasm-2.16.03.tar.gz | 1688160 | `5bc940dd8a4245686976a8f7e96ba9340a0915f2d5b88356874890e207bdb581` | 2026-11-20T08:24Z | tofu; https copy matched 2026-11-20 |
| https://pkg-config.freedesktop.org/releases/pkg-config-0.29.2.tar.gz | 2016830 | `6fc69c01688c9458a57eb9a1664c9aba372ccda420a02bf4429fe610e7e7d591` | 2026-11-20T08:24Z | tofu |
| https://www.zlib.net/fossils/zlib-1.3.2.tar.gz | 1502830 | `bb329a0a2cd0274d05519d61c667c062e06990d72e125ee2dfa8de64f0119d16` | 2026-11-20T08:25Z | tofu |
| https://github.com/openssl/openssl/releases/download/openssl-3.6.1/openssl-3.6.1.tar.gz | 54891951 | `b1bfedcd5b289ff22aee87c9d600f515767ebf45f77168cb6d64f231f518a82e` | 2026-11-20T08:25Z | tofu |
| https://cmake.org/files/v3.31/cmake-3.31.8.tar.gz | 11713806 | `e3cde3ca83dc2d3212105326b8f1b565116be808394384007e7ef1c253af6caa` | 2026-11-20T08:26Z | tofu |
| https://github.com/ninja-build/ninja/archive/refs/tags/v1.13.2.tar.gz | 292385 | `974d6b2f4eeefa25625d34da3cb36bdcebe7fbce40f4c16ac0835fd1c0cbae17` | 2026-11-20T08:28Z | tofu |
| https://download.gnome.org/sources/libxml2/2.15/libxml2-2.15.3.tar.xz | 3152452 | `78262a6e7ac170d6528ebfe2efccdf220191a5af6a6cd61ea4a9a9a5042c7a07` | 2026-11-20T08:28Z | tofu |
| https://github.com/fribidi/fribidi/releases/download/v1.0.16/fribidi-1.0.16.tar.xz | 1098260 | `1b1cde5b235d40479e91be2f0e88a309e3214c8ab470ec8a2744d82a5a9ea05c` | 2026-11-20T08:29Z | tofu |
| https://download.savannah.gnu.org/releases/freetype/freetype-2.13.0.tar.gz | 3819054 | `a7aca0e532a276ea8d85bd31149f0a74c33d19c8d287116ef8f5f8357b4f1f80` | 2026-11-20T08:29Z | tofu |
| https://gitlab.freedesktop.org/api/v4/projects/890/packages/generic/fontconfig/2.17.1/fontconfig-2.17.1.tar.xz | 1326312 | `9f5cae93f4fffc1fbc05ae99cdfc708cd60dfd6612ffc0512827025c026fa541` | 2026-11-20T08:29Z | tofu |
| https://github.com/harfbuzz/harfbuzz/releases/download/14.2.0/harfbuzz-14.2.0.tar.xz | 19555096 | `94017020f96d025bb66ae91574e4cf334bcad23e8175a8a40565b3721bc2eaff` | 2026-11-20T08:29Z | tofu |
| https://www.libsdl.org/release/SDL2-2.32.10.tar.gz | 7630262 | `5f5993c530f084535c65a6879e9b26ad441169b3e25d789d83287040a9ca5165` | 2026-11-20T08:30Z | tofu |
| https://github.com/google/snappy/archive/refs/tags/1.2.2.tar.gz | 1108618 | `90f74bc1fbf78a6c56b3c4a082a05103b3a56bb17bca1a27e052ea11723292dc` | 2026-11-20T08:30Z | tofu |
| https://github.com/Haivision/srt/archive/refs/tags/v1.5.4.tar.gz | 1743040 | `d0a8b600fe1b4eaaf6277530e3cfc8f15b8ce4035f16af4a5eb5d4b123640cdd` | 2026-11-20T08:30Z | tofu |
| https://github.com/Netflix/vmaf/archive/refs/tags/v3.1.0.tar.gz | 18184375 | `80090e29d7fd0db472ddc663513f5be89bc936815e62b767e630c1d627279fe2` | 2026-11-20T08:30Z | tofu |
| https://github.com/libass/libass/releases/download/0.17.4/libass-0.17.4.tar.gz | 635871 | `a886b3b80867f437bc55cff3280a652bfa0d37b43d2aff39ddf3c4f288b8c5a8` | 2026-11-20T08:30Z | tofu |
| https://github.com/stoth68000/libklvanc/archive/refs/tags/vid.obe.1.6.0.tar.gz | 53167296 | `5076ca48455a4ef4ead2cd880ba189b21937a9ad8fd458adfc133d7bb1c948c3` | 2026-11-20T08:30Z | tofu |
| https://ftp.osuosl.org/pub/xiph/releases/ogg/libogg-1.3.6.tar.gz | 604469 | `83e6704730683d004d20e21b8f7f55dcb3383cdf84c0daedf30bde175f774638` | 2026-11-20T08:42Z | tofu |
| https://github.com/sekrit-twc/zimg/archive/refs/tags/release-3.0.6.tar.gz | 326725 | `be89390f13a5c9b2388ce0f44a5e89364a20c1c57ce46d382b1fcc3967057577` | 2026-11-20T08:42Z | tofu |
| https://sourceforge.net/projects/zapping/files/zvbi/0.2.35/zvbi-0.2.35.tar.bz2/download | 1047761 | `fc883c34111a487c4a783f91b1b2bb5610d8d8e58dcba80c7ab31e67e4765318` | 2026-11-20T08:42Z | tofu |
| https://storage.googleapis.com/aom-releases/libaom-3.13.3.tar.gz | 6256836 | `446a4ae9741cb8f3eeb98c949d25f91b48cb2b8569cae975c4b737392e9024fc` | 2026-11-20T08:43Z | tofu |
| https://code.videolan.org/videolan/dav1d/-/archive/1.5.3/dav1d-1.5.3.tar.gz | 1713950 | `cbe212b02faf8c6eed5b6d55ef8a6e363aaab83f15112e960701a9c3df813686` | 2026-11-20T08:43Z | tofu |
| https://github.com/cisco/openh264/archive/v2.6.0.tar.gz | 60302243 | `558544ad358283a7ab2930d69a9ceddf913f4a51ee9bf1bfb9e377322af81a69` | 2026-11-20T08:43Z | tofu |
| https://github.com/uclouvain/openjpeg/archive/refs/tags/v2.5.4.tar.gz | 2157028 | `a695fbe19c0165f295a8531b1e4e855cd94d0875d2f88ec4b61080677e27188a` | 2026-11-20T08:43Z | tofu |
| https://github.com/xiph/rav1e/archive/refs/tags/v0.8.1.tar.gz | 3040879 | `06d1523955fb6ed9cf9992eace772121067cca7e8926988a1ee16492febbe01e` | 2026-11-20T08:52Z | tofu |
| https://gitlab.com/AOMediaCodec/SVT-AV1/-/archive/v3.1.2/SVT-AV1-v3.1.2.tar.gz | 10909754 | `d0d73bfea42fdcc1222272bf2b0e2319e9df5574721298090c3d28315586ecb1` | 2026-11-20T08:53Z | tofu |
| https://github.com/webmproject/libvpx/archive/v1.16.0.tar.gz | 5635379 | `7a479a3c66b9f5d5542a4c6a1b7d3768a983b1e5c14c60a9396edc9b649e015c` | 2026-11-20T08:53Z | tofu |
| https://github.com/fraunhoferhhi/vvenc/archive/refs/tags/v1.14.0.tar.gz | 2352859 | `dd43d061d59dbc0d9b9ae5b99cb40672877dd811646228938f065798939ee174` | 2026-11-20T08:53Z | tofu |
| https://github.com/webmproject/libwebp/archive/refs/tags/v1.6.0.tar.gz | 3833512 | `93a852c2b3efafee3723efd4636de855b46f9fe1efddd607e1f42f60fc8f2136` | 2026-11-20T08:53Z | tofu |
| https://code.videolan.org/videolan/x264/-/archive/0480cb05fa188d37ae87e8f4fd8f1aea3711f7ee/x264-0480cb05fa188d37ae87e8f4fd8f1aea3711f7ee.tar.gz | 1040667 | `d0967a1348c85dfde363bb52610403be898171493100561efa0dd05d5fd1ae50` | 2026-11-20T18:10Z | pinned commit (build-script-05581a4-pins.patch); same tree as the 2026-11-20 master snapshot |
| https://bitbucket.org/multicoreware/x265_git/get/4.1.tar.gz | 1726307 | `7d23cdcdbd510728202c0dfbf7c51eda26a395de2096c504c2b10d6035711102` | 2026-11-20T08:53Z | tofu |
| https://unlimited.dl.sourceforge.net/project/lame/lame/3.100/lame-3.100.tar.gz | 1524133 | `ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e` | 2026-11-20T08:54Z | tofu |
| https://downloads.xiph.org/releases/opus/opus-1.6.1.tar.gz | 10472813 | `6ffcb593207be92584df15b32466ed64bbec99109f007c82205f0194572411a1` | 2026-11-20T08:54Z | tofu |
| https://ftp.osuosl.org/pub/xiph/releases/vorbis/libvorbis-1.3.7.tar.gz | 1658963 | `0e982409a9c3fc82ee06e08205b1355e5c6aa4c36bca58146ef399621b0ce5ab` | 2026-11-20T08:54Z | tofu |
| https://ffmpeg.org/releases/ffmpeg-8.1.1.tar.bz2 | 14087042 | `b08594a47ca475ddda21c7990d8e9e3ceb5cd74f9709b4b5995b24d11cafa467` | 2026-11-20T09:00Z | tofu |
| http://downloads.xiph.org/releases/theora/libtheora-1.2.0.tar.gz | 2535283 | `279327339903b544c28a92aeada7d0dcfd0397b59c2f368cc698ac56f515906e` | 2026-11-20T09:17Z | tofu; https copy matched 2026-11-20 |

`x264-master.tar.gz` (used only by the GPL library set) is the x264 master branch at commit `0480cb05fa188d37ae87e8f4fd8f1aea3711f7ee` (read from the archive with `git get-tar-commit-id`). `ffmpeg-8.1.1.tar.bz2` also has a good signature from the FFmpeg release key (checked with its `.asc`).

