# GiVo Server build scripts

GiVo Server bundles a few open-source programs next to its own code: Comskip (commercial detection), whisper-cli from whisper.cpp (automatic captions) and FFmpeg (recording). This repository holds the scripts we build those programs with, so anyone can rebuild them from the same sources. It holds no GiVo Server code.

## What is here

| Script | Builds | Version | License of the result |
|---|---|---|---|
| `comskip/build-comskip-macos.sh` | comskip for macOS (Apple silicon and Intel, one universal program) | Comskip 0.83.001 at commit a140b6a, with FFmpeg 7.1.1 (decode only) and argtable 2.13 | GPL-2.0 |
| `comskip/build-comskip-windows.sh` | comskip.exe for Windows x64 and Windows on ARM | the same, plus zlib 1.3.2 | GPL-2.0 |
| `linux/Dockerfile.tools` | static comskip and whisper-cli for Linux x86-64 and ARM64 | as above; whisper.cpp v1.9.1 | GPL-2.0 / MIT |
| `whisper/build-whisper-macos.sh` | whisper-cli for Apple silicon (Metal) | whisper.cpp v1.9.1 | MIT |
| `whisper/build-whisper-windows-arm64.sh` | whisper-cli.exe for Windows on ARM (one program, no OpenMP) | whisper.cpp v1.9.1 | MIT |
| `whisper/build-whisper-windows-x64.sh` | whisper-cli.exe for Windows x64, its DLLs and ggml's CPU levels (no Visual C++ or OpenMP runtime) | whisper.cpp v1.9.1 | MIT |
| `ffmpeg/build-ffmpeg-macos.sh` | ffmpeg and ffprobe for macOS (one slice per run; `ffmpeg/join-macos.sh` makes the universal pair), with Martin Riedl's public build script at a fixed commit plus `ffmpeg/build-script-05581a4-pins.patch` | FFmpeg 8.1.1, the full library set (on Intel without rav1e) | GPL-3.0-or-later |
| `ffmpeg/fetch-ffmpeg-windows.sh` | nothing: it downloads and checks the BtbN builds of FFmpeg we ship on Windows | N-125365-g9a01c1cb6a | GPL-3.0-or-later |

Helper files go with the macOS FFmpeg script: `ffmpeg/curl-shim.sh` serves each source archive only when it matches `ffmpeg/macos-sources.tsv`; `ffmpeg/build-script-05581a4-pins.patch` is the one change made to Martin Riedl's script (x264 at a fixed commit instead of its master branch, rav1e's crates exactly as locked); `ffmpeg/join-macos.sh` joins the two slices; `ffmpeg/gen-macos-library-notices.sh` collects the license and patent notices of every library and Rust crate inside the build; `ffmpeg/conformance-macos.sh` runs every FFmpeg command shape GiVo Server uses against two builds and compares the results.

Every source a script downloads is pinned by version or commit and checked against its SHA-256. No script changes the source of any program. `SOURCES.md` lists every source archive with its address and checksum.

whisper.cpp v1.9.1 for Windows is built here on both architectures (`whisper/build-whisper-windows-x64.sh`, `whisper/build-whisper-windows-arm64.sh`) with llvm-mingw, so it needs no Visual C++ or OpenMP runtime beside it. On x64, ggml's CPU code is built once per x86-64 level (`ggml-cpu-*.dll`, from plain x86-64 to AVX-512) and the best one for the PC is loaded when whisper-cli starts; the ARM64 build is one static program for armv8.2-a with dot product.

## What you need

- **macOS builds:** a Mac with Xcode (we use Xcode 27.2) and Homebrew with `autoconf automake libtool pkgconf nasm cmake meson` (meson 1.12.1), plus Rust with cargo-c for rav1e in the Apple-silicon slice. The Intel half of FFmpeg is built on an Apple silicon Mac under Rosetta 2 (meson then runs under its own Python and is told the machine is x86_64; see the script header), or on an Intel Mac. About 15 GB free.
- **Windows builds:** the same Mac, plus the llvm-mingw 20261006 UCRT release for macOS (`llvm-mingw-20261006-ucrt-macos-universal.tar.xz`, SHA-256 `a7a19b11048e89372637d26279cdb7c430ed3cf8c1e224310421312bf986ebf6`), extracted; pass its folder as `LLVM_MINGW`.
- **Linux builds:** Docker with buildx (QEMU emulation for the architecture you are not on).
- Network access to the upstream sources listed in `SOURCES.md`.

## How to run the two scripts that take more than a folder

**macOS FFmpeg**, one slice per Mac (Apple silicon here; Intel on an Intel Mac or under Rosetta 2):

    VARIANT=gpl SOURCE_CACHE=/path/to/ffmpeg-sources \
      ffmpeg/build-ffmpeg-macos.sh /path/to/out-arm64
    # move /Volumes/G-SSD/ffmpeg-macos-build aside, then the Intel slice under Rosetta 2:
    VARIANT=gpl SOURCE_CACHE=/path/to/ffmpeg-sources \
      arch -x86_64 /bin/bash ffmpeg/build-ffmpeg-macos.sh /path/to/out-x86_64
    ffmpeg/join-macos.sh /path/to/out-arm64 /path/to/out-x86_64

- `SOURCE_CACHE` may start empty. Each archive in `ffmpeg/macos-sources.tsv` is downloaded once (https first) and kept only when its SHA-256 matches. Any archive not in the list stops the build.
- The build always runs in `/Volumes/G-SSD/ffmpeg-macos-build`, which must not exist yet. That path is built into ffmpeg (its configuration line and the folders where OpenSSL and fontconfig look for their settings), so the same bytes come only from the same path. Without a drive named G-SSD, a disk image works, with no admin rights:

      hdiutil create -size 20g -type SPARSE -fs APFS -volname G-SSD ffmpeg-build
      hdiutil attach ffmpeg-build.sparseimage

  It is not under a home folder (that would put an account name into every copy) and not under `/tmp` (any account on a Mac can create folders there).

**Windows comskip and whisper-cli** need the llvm-mingw release archive, which the scripts check before they unpack it into the work folder:

    ARCH=x64 LLVM_MINGW_ARCHIVE=/path/to/llvm-mingw-20261006-ucrt-macos-universal.tar.xz \
      comskip/build-comskip-windows.sh /path/to/empty-work /path/to/out

Every script uses only an empty work folder, or one it made itself; it never deletes anything else.

## Source code of the programs we ship

Each GiVo Server release has a release here (tag `server-<build>`). Its files are the complete corresponding source of the programs that release ships that we build or pass on, one archive per program:

- `givo-server-<build>-macos-ffmpeg-8.1.1-source.tar`: the 36 source archives, the Rust crates of rav1e, Martin Riedl's script at the pinned commit with our one patch, and our scripts;
- `givo-server-<build>-windows-ffmpeg-<version>-source.tar`: FFmpeg at the build's commit, BtbN's build scripts at its release tag, and every library those scripts pin;
- `givo-server-<build>-comskip-<version>-source.tar`: Comskip at its commit, with the FFmpeg, argtable and zlib archives it is built with, and our scripts;
- `givo-server-<build>-linux-glibc-<version>-source.tar`: Debian's glibc source package for the static Linux tools, with whisper.cpp's source so whisper-cli can be relinked;
- `givo-server-<build>-docker-debian-sources.tar`: Debian's source packages, at the installed versions, of every package in the Docker image whose copyright file names a GPL-family license (FFmpeg among them).

Each holds a README saying which download and build it belongs to, and a `SHA256SUMS` file; the release's own `SHA256SUMS` covers the archives. `SOURCES.md` lists each source with its address and checksum. The FFmpeg for Windows that GiVo Server 91 to 101 included has its own release, `server-101-windows-ffmpeg`, since its original builder no longer publishes it. For Comskip (GPL-2.0) our commitment is the written offer: for at least three years after we last distribute a build, we send its source to anyone who asks at support@givostreamapp.com, for no more than our cost of sending it; its copy in the releases is there for convenience.

## License of this repository

The scripts in this repository are under the MIT License (`LICENSE`). The programs they build keep their own licenses, listed above.

## How to compare a rebuild with ours

Builds made on another machine are not guaranteed to be bit-identical: compilers and SDKs differ. Compare the version strings and, for FFmpeg, `ffmpeg -buildconf`. `SOURCES.md` lists the SHA-256 of each program we shipped, for reference.

The macOS FFmpeg is the exception we aim for: with Xcode 27.2, meson 1.12.1 and the fixed build folder, two builds of ours at one path came out byte-identical (the script sets `SOURCE_DATE_EPOCH` to the build script's commit date and `ZERO_AR_DATE=1`). The LGPL Apple-silicon build at that folder is ffmpeg `5a21676c912d22ecc7a118edfeb95be1b0fbbb4f7e2d4a024cab583ef9c010d2` and ffprobe `d1b50b794582321827e62422cc737840e5fa260c23f489e6924f40e29fccdc23`.

## Questions

Write to support@givostreamapp.com.
