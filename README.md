# Android build scripts for CMake

Everything required to build mainly C++ focused android packages. No requirements outside of a working android SDK & NDK

The purpose of this is to be used as an alternative to setting up a gradle project and using it as a master build system when the only thing required is a minimal java layer with a larger C++ code base

## Requirements

- Android SDK
- Android NDK
- JDK
- 7zip

## Usage

Assuming the following tree

```plain
├── java
│   ├── AndroidManifest.xml
│   ├── res
│   │   ├── mipmap-hdpi
│   │   │   └── ic_launcher.png
│   │   ├── ...
│   │   └── values
│   │       ├── colors.xml
│   │       ├── strings.xml
│   │       └── styles.xml
│   └── src
│       ├── AppActivity.java
│       ├── ...
...
```

You can define an executable android package as follows

```cmake
add_library(NativeCode SHARED test.cpp)

file(GLOB_RECURSE ANDROID_SOURCES "java/src/*")
add_android_package(
    NAME app
    SOURCES ${ANDROID_SOURCES}
    MANIFEST java/AndroidManifest.xml
    RES_PATH java/res
    LIB_TARGETS NativeCode
)
```

This creates a target named app that build app.apk
The java sources and resources / manifest are compiled and bundled into an APK together with the shared native libraries passed in `LIB_TARGETS`

## Limitations

- Only does debug signing on APK
- Only includes the platform's android.jar

## Configuration (vscode)

Using the vscode CMake extension you can add tool kits like this:

```json
{
  "name": "aarch64-none-linux-android-30",
  "toolchainFile": "<PATH_TO_NDK>\\build\\cmake\\android.toolchain.cmake",
  "cmakeSettings": {
    "JAVA_HOME": "<PATH_TO_JDK>",
    "ANDROID_SDK_ROOT": "<PATH_TO_SDK>",
    "ANDROID_ABI": "arm64-v8a",
    "ANDROID_PLATFORM": "android-30",
    "ANDROID_TOOLS_VERSION": "32.0.0",
  },
  "preferredGenerator": {
    "name": "Ninja"
  },
}
```

And modify the settings as needed

## Configuration (command line)

Same as above but pass the arguments on the command line:

```sh
cmake -Bbuild -DJAVA_HOME=... -DANDROID_SDK_ROOT=... -DANDROID_ABI=... -DANDROID_PLATFORM=... -DANDROID_TOOLS_VERSION=.. -DTOOLCHAIN_FILE=<PATH_TO_NDK>/build/cmake/android.toolchain.cmake
```
