# Mason

Build automation for the Mapbox C++ core

## Installation

You need to install Mason to your user directory into `~/.mason`.

```bash
git clone https://github.com/mapbox/mason.git ~/.mason
sudo ln -s ~/.mason/mason /usr/local/bin/mason
```

The second line is optional.

## Usage

Most commands are structured like this:

```bash
mason <command> <library> <version>
```

The `command` can be one of the following

* `install`: Installs the specified library/version
* `remove`: Removes the specified library/version
* `build`: Forces a build from source (= skip pre-built binary detection)
* `publish`: Uploads the built binaries to the S3 bucket
* `prefix`: Prints the absolute path to the library installation directory
* `version`: Prints the actual version of the library (only useful when version is `system`)
* `cflags`: Prints C/C++ compiler flags
* `ldflags`: Prints linker flags

Apart from library/version specific actions, you can also run these commands without library/version:

* `selfupdate`: Updates mason itself
* `init`: Creates a new Git repository named after the current folder name and publishes it to GitHub

### `install`

```bash
$ mason install libuv 0.11.29
* Loading install script 'https://github.com/mapbox/mason/blob/libuv-0.11.29/script.sh'...
######################################################################## 100.0%
* Downloading binary package osx-10.10/libuv/0.11.29.tar.gz...
######################################################################## 100.0%
* Installed binary package at /Users/user/mason_packages/osx-10.10/libuv/0.11.29
```

Installs [libuv](https://github.com/joyent/libuv) into the current folder in the `mason_packages` directory. Libraries are versioned by platform and version number, so you can install several different versions of the same library along each other. Similarly, you can also install libraries for different platforms alongside each other, for example library binaries for OS X and iOS.

Installation happens in multiple phases: First, Mason obtains the installation script for the requested library/version by either downloading it from Github, or loading the cached version from the `mason_packages/.scripts` folder if it exists.

If the specified library/version is already present for this platform, nothing further happens. This means you can run the `install` command multiple times (e.g. as part of a configuration script) without doing unnecessary work.

Next, Mason checks whether there are pre-built binaries available in the S3 bucket for the current platform. If that is the case, they are downloaded and unzipped and the installation is complete.

If no pre-built binaries are available, Mason is going to build the library according to the script in the `mason_packages/.build` folder, and install into the platform- and library-specific directory.


### `remove`

```bash
$ mason remove libuv 0.11.29
* Removing existing package...
/Users/user/mason_packages/osx-10.10/libuv/0.11.29/include/uv-darwin.h
[...]
/Users/user/mason_packages/osx-10.10/libuv/0.11.29
```

Removes the specified library/version from the package directory.

### `build`

This command works like the `install` command, except that it *doesn't* check for existing library installations, and that it *doesn't* check for pre-built binaries. I.e. it first removes the current installation and *always* builds the library from source. This is useful when you are working on a build script and want to fresh builds.

### `publish`

Creates a gzipped tarball of the specified platform/library/version and uploads it to the `mason-binaries` S3 bucket. If you want to use this feature, you need write access to the bucket and need to specify the environment variables `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`.

### `prefix`

```bash
~ $ mason prefix libuv 0.11.29
/Users/user/mason_packages/osx-10.10/libuv/0.11.29
```

This prints the absolute path to the installation directory of the the library/version. Likely, this folder has the typical `include` and `lib` folders.

### `cflags`

```bash
~ $ mason cflags libuv 0.11.29
-I/Users/user/mason_packages/osx-10.10/libuv/0.11.29/include
```

Prints the C/C++ compiler flags that are required to compile source code with this library. Likely, this is just the include path, but may also contain other flags.

### `ldflags`

```bash
~ $ mason ldflags libuv 0.11.29
-L/Users/user/mason_packages/osx-10.10/libuv/0.11.29/lib -luv -lpthread -ldl
```

Prints the linker flags that are required to link against this library.


## Writing build scripts

Every build script has its own branch on https://github.com/mapbox/mason. The branches are named `library-version`, e.g. [`libuv-0.11.29`](https://github.com/mapbox/mason/tree/libuv-0.11.29). The repository must contain a file called `script.sh`, which is structured like this:

```bash
#!/usr/bin/env bash

MASON_NAME=libuv
MASON_VERSION=0.11.29
MASON_LIB_FILE=lib/libuv.a
MASON_PKGCONFIG_FILE=lib/pkgconfig/libuv.pc
```

Declare these variables first. `MASON_NAME` and `MASON_VERSION` are mandatory. If the install script build a static library, specify the relative path in the installation directory in `MASON_LIB_FILE`. This is used to check whether an installation actually exists before proceeding to download/build the library anew. You can optionally specify `MASON_PKGCONFIG_FILE` as the relative path to the pig-config file if the library has one. If the library doesn't have one, you need to override the functions `mason_cflags` and `mason_ldflags` (see below).

Then, we're loading the build system with

```bash
. ~/.mason/mason.sh
```

Next, we're defining a function that obtains the source code and unzips it:

```bash
function mason_load_source {
    mason_download \
        https://github.com/joyent/libuv/archive/v0.11.29.tar.gz \
        5bf49a8652f680557cbaf335a160187b2da3bf7f

    mason_extract_tar_gz

    export MASON_BUILD_PATH=${MASON_ROOT}/.build/libuv-${MASON_VERSION}
}
```

In that function, you should use `mason_download` as a shortcut to download the tarball. The second argument to is a hash generated with `git hash-object` and used to verify that the source code downloaded matches the expected file. The function also caches downloaded tarballs in the `mason_packages/.cache` folder.

`mason_extract_tar_gz` unpacks the archive into the `mason_packages/.build` folder. If the tarball is BZip2 compressed, you can also use `mason_extract_tar_bz2` instead.

Lastly, the `MASON_BUILD_PATH` variable contains the path to the unpacked folder inside the `.build` directory.

Then, you can optionally specify a function that is run before compiling, e.g. a script that generates configuration files:

```bash
function mason_prepare_compile {
    ./autogen.sh
}
```

The heart of the script is the `mason_compile` function because it performs the actual build of the source code. There are a few variables available that you need to use to make sure that the package will work correctly.

```bash
function mason_compile {
    ./configure \
        --prefix=${MASON_PREFIX} \
        ${MASON_HOST_ARG} \
        --enable-static \
        --disable-shared \
        --disable-dependency-tracking

    make install -j${MASON_CONCURRENCY}
}
```

In particular, you have to set the build system's installation prefix to `MASON_PREFIX`. For cross-platform builds, you have to specify the `MASON_HOST_ARG`, which is empty for regular builds and is set to the correct host platform for cross-compiles (e.g. iOS builds use `--host=arm-apple-darwin`).

If the build system supports building concurrently, you can tell it do do so by providing the number of parallel tasks from `MASON_CONCURRENCY`.


Next, the `mason_clean` function tells Mason how to clean up the build folder. This is required for multi-architecture builds. E.g. iOS builds perform a Simulator (Intel architecture) build first, then an iOS (ARM architecture) build. The results are `lipo`ed into one universal archive file.

```bash
function mason_clean {
    make clean
}
```

Finally, we're going to run the everything:

```bash
mason_run "$@"
```

### Variables

Name | Description
---|---
`MASON_ROOT` | Absolute path the `mason_packages` directory. Example: `/Users/user/mason_packages`.
`MASON_PLATFORM` | Platform of` the current invocation. Currently one of `osx`, `ios` or `linux`.
`MASON_PLATFORM_VERSION` | Version of the platform. It must include the architecture if the produced binaries are architecture-specific (e.g. on Linux). Example: `10.10`
`MASON_NAME` | Name specified in the `script.sh` file. Example: `libuv`
`MASON_VERSION` | Version specified in the `script.sh` file. Example: `0.11.29`
`MASON_SLUG` | Combination of the name and version. Example: `libuv-0.11.29`
`MASON_PREFIX` | Absolute installation path. Example: `/Users/user/mason_packages/osx-10.10/libuv/0.11.29`
`MASON_SCRIPT` | Absolute path to the install script. Example: `/Users/user/mason_packages/.scripts/libuv-0.11.29.sh`
`MASON_BUILD_PATH` | Absolute path to the build root. Example: `/Users/user/mason_packages/.build/libuv-0.11.29`
`MASON_BUCKET` | S3 bucket that is used for storing pre-built binary packages. Example: `mason-binaries`
`MASON_BINARIES` | Relative path to the gzipped tarball in the `.binaries` directory. Example: `osx-10.10/libuv/0.11.29.tar.gz`
`MASON_BINARIES_PATH` | Absolute path to the gzipped tarball. Example: `/Users/user/mason_packages/.binaries/osx-10.10/libuv/0.11.29.tar.gz`
`MASON_CONCURRENCY` | Number of CPU cores. Example: `8`
`MASON_HOST_ARG` | Cross-compilation arguments. Example: `--host=x86_64-apple-darwin`
`MASON_LIB_FILE` | Relative path to the library file in the install directory. Example: `lib/libuv.a`
`MASON_PKGCONFIG_FILE` | Relative path to the pkg-config file in the install directory.  Example: `lib/pkgconfig/libuv.pc`
`MASON_XCODE_ROOT` | OS X specific; Path to the Xcode Developer directory. Example: `/Applications/Xcode.app/Contents/Developer`



### Customization

In addition to the override functions described above, you can also override the `mason_cflags` and `mason_ldflags` functions. By default, they're using `pkg-config` to determine these flags and print them to standard output. If a library doesn't include a `.pc` file, or has some other mechanism for determining the build flags, you can run them instead:


```bash
function mason_ldflags {
    ${MASON_PREFIX}/bin/curl-config --static-libs`
}
```

### System packages

Some packages ship with operating systems, or can be easily installed with operating-specific package managers. For example, `libpng` is available on most systems and the version you're using doesn't really matter since it is mature and hasn't added any significant new APIs in recent years. To create a system package for it, use this `script.sh` file:


```bash
#!/usr/bin/env bash

MASON_NAME=libpng
MASON_VERSION=system
MASON_SYSTEM_PACKAGE=true

. ~/.mason/mason.sh

if [ ! $(pkg-config libpng --exists; echo $?) = 0 ]; then
    mason_error "Cannot find libpng with pkg-config"
    exit 1
fi

function mason_system_version {
    mkdir -p "${MASON_PREFIX}"
    cd "${MASON_PREFIX}"
    if [ ! -f version ]; then
        echo "#include <png.h>
#include <stdio.h>
#include <assert.h>
int main() {
    assert(PNG_LIBPNG_VER == png_access_version_number());
    printf(\"%s\", PNG_LIBPNG_VER_STRING);
    return 0;
}
" > version.c && ${CC:-cc} version.c $(mason_cflags) $(mason_ldflags) -o version
    fi
    ./version
}

function mason_compile {
    :
}

function mason_cflags {
    pkg-config libpng --cflags
}

function mason_ldflags {
    pkg-config libpng --libs
}

mason_run "$@"
```

System packages are marked with `MASON_SYSTEM_PACKAGE=true`. We're also first using `pkg-config` to check whether the library is present at all. The `mason_system_version` function creates a small executable which outputs the actual version. It is the only thing that is cached in the installation directory.

We have to override the `mason_cflags` and `mason_ldflags` commands since the regular commands return flags for static libraries, but in the case of system packages, we want to dynamically link against the package.

## Troubleshooting

Install scripts are cached in the `mason_packages/.scripts` directory. If you update script in the Mason repository, and your changes aren't getting applied, make sure you delete the script from that directory.

Similarly, downloaded source tarballs are cached in `mason_packages/.cache`. If for some reason the initial download failed, but it still left a file in that directory, make sure you delete the partial download there.