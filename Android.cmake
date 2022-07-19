# Required variables
# ANDROID_ABI:           The target ABI (e.g. "arm64-v8a")
# ANDROID_PLATFORM:      The target android platform (e.g. "android-24")
# ANDROID_SDK_ROOT:      Path to the android SDK (e.g. "A:\\Android")
# ANDROID_TOOLS_VERSION: Version of the android build tools to use (e.g. "32.0.0")
# JAVA_HOME:             Path to the JDK (e.g. "A:\\Java\\jdk-11)

option(ANDROID_DEBUG "Debug mode")
if(${ANDROID_DEBUG} OR CMAKE_BUILD_TYPE MATCHES "Debug")
  set(_ANDROID_DEBUG ON)
endif()

if(NOT ANDROID)
  message(FATAL_ERROR "Android.cmake was included but you're not building for android")
endif()

macro(android_sdk_from_env NAME)
  if(NOT ANDROID_SDK_ROOT AND DEFINED ENV{${NAME}})
    message(STATUS "Using android SDK from ANDROID_HOME=$ENV{${NAME}}")
    set(ANDROID_SDK_ROOT $ENV{${NAME}})
  endif()
endmacro()

find_package(Java REQUIRED)
include(UseJava)

option(ANDROID_SDK_ROOT "Path to the android SDK root folder")
android_sdk_from_env("ANDROID_HOME")
android_sdk_from_env("ANDROID_SDK_ROOT")
android_sdk_from_env("ANDROID_SDK")
if(NOT ANDROID_SDK_ROOT)
  message(FATAL_ERROR "ANDROID_SDK_ROOT not set")
endif()
message(STATUS "Using Android SDK: ${ANDROID_SDK_ROOT}")

option(ANDROID_TOOLS_VERSION "Version of the build tools to use")
if(NOT ANDROID_TOOLS_VERSION)
  message(FATAL_ERROR "ANDROID_TOOLS_VERSION not set")
endif()

set(ANDROID_BUILD_TOOLS_PATH ${ANDROID_SDK_ROOT}/build-tools/${ANDROID_TOOLS_VERSION})
message(STATUS "Using Android build tools: ${ANDROID_BUILD_TOOLS_PATH}")

set(ANDROID_PLATFORM_PATH ${ANDROID_SDK_ROOT}/platforms/${ANDROID_PLATFORM})

# Find android SDK tools
find_program(ANDROID_AAPT2 NAMES "aapt2" PATHS ${ANDROID_BUILD_TOOLS_PATH} REQUIRED NO_DEFAULT_PATH NO_SYSTEM_ENVIRONMENT_PATH NO_CMAKE_FIND_ROOT_PATH)
find_program(ANDROID_ZIPALIGN NAMES "zipalign" PATHS ${ANDROID_BUILD_TOOLS_PATH} REQUIRED NO_DEFAULT_PATH NO_SYSTEM_ENVIRONMENT_PATH NO_CMAKE_FIND_ROOT_PATH)
find_file(ANDROID_D8_JAR NAMES "d8.jar" PATHS "${ANDROID_BUILD_TOOLS_PATH}/lib" REQUIRED NO_DEFAULT_PATH NO_SYSTEM_ENVIRONMENT_PATH NO_CMAKE_FIND_ROOT_PATH)
find_program(ANDROID_APKSIGNER_JAR NAMES "apksigner.jar" PATHS "${ANDROID_BUILD_TOOLS_PATH}/lib" REQUIRED NO_DEFAULT_PATH NO_SYSTEM_ENVIRONMENT_PATH NO_CMAKE_FIND_ROOT_PATH)

# Required for manipulating zip files
option(SEVEN_ZIP_PATH "Path to where the 7z binary is")
find_program(SEVEN_ZIP NAMES "7z" PATHS ${SEVEN_ZIP_PATH} REQUIRED)

# Find keytool
file(REAL_PATH "${Java_JAVA_EXECUTABLE}/.." JDK_PATH)
find_program(Java_KEYTOOL NAMES "keytool" PATHS ${JDK_PATH} REQUIRED NO_DEFAULT_PATH NO_SYSTEM_ENVIRONMENT_PATH NO_CMAKE_FIND_ROOT_PATH)

set(DEBUG_KEYSTORE_PATH ${CMAKE_BINARY_DIR}/debug.keystore)
set(DEBUG_KEYSTORE_KEY androiddebugkey)
set(DEBUG_KEYSTORE_PASS android)
function(ensure_debug_keystore)
  if(NOT EXISTS ${DEBUG_KEYSTORE_PATH})
    message(STATUS "Generating android debug keystore")
    execute_process(COMMAND ${Java_KEYTOOL} -genkey -v -dname "CN=debug" -keystore ${DEBUG_KEYSTORE_PATH} -storepass ${DEBUG_KEYSTORE_PASS} -keypass ${DEBUG_KEYSTORE_PASS} -alias ${DEBUG_KEYSTORE_KEY} -keyalg RSA -keysize 2048 -validity 10000)
  endif()
endfunction()
ensure_debug_keystore()

function(add_android_package)
  set(OPTS)
  set(ARGS
    NAME            # (Required) The name of the package to build
    RES_PATH        # (Required) Path to android resources
    MANIFEST        # (Required) Android manifest path
  )
  set(MULTI_ARGS
    SOURCES            # (Required) Android java sources
    LIB_TARGETS        # Native libs to include
  )
  cmake_parse_arguments(APK "${OPTS}" "${ARGS}" "${MULTI_ARGS}" ${ARGN})
  message(STATUS "add_android_package(${APK_NAME})")

  set(JAR_NAME "${APK_NAME}_javasrc")

  message(STATUS " Java source files: ${APK_SOURCES}")
  add_jar(${JAR_NAME}
    SOURCES ${APK_SOURCES}
    INCLUDE_JARS ${ANDROID_PLATFORM_PATH}/android.jar
  )
  set(JAR_PATH "${JAR_NAME}.jar")

  set(CLASSES_DEX_PATH ${CMAKE_CURRENT_BINARY_DIR}/${APK_NAME}-dex)
  file(MAKE_DIRECTORY ${CLASSES_DEX_PATH})
  add_custom_command(
    OUTPUT ${CLASSES_DEX_PATH}/classes.dex
    COMMAND ${Java_JAVA_EXECUTABLE} -cp ${ANDROID_D8_JAR} com.android.tools.r8.D8 ${JAR_PATH} --output ${CLASSES_DEX_PATH}
    DEPENDS ${JAR_PATH}
    COMMENT "Dexing"
    USES_TERMINAL
  )

  if(NOT IS_ABSOLUTE APK_RES_PATH)
    file(REAL_PATH ${APK_RES_PATH} APK_RES_PATH)
  endif()

  # Compile resources
  file(GLOB_RECURSE RESOURCE_FILES "${APK_RES_PATH}/*")
  foreach(RES_FILE ${RESOURCE_FILES})
    file(RELATIVE_PATH REL_RES_PATH ${APK_RES_PATH} ${RES_FILE})
    get_filename_component(RES_NAME_WE ${RES_FILE} NAME_WE)
    get_filename_component(REL_RES_DIR ${REL_RES_PATH} DIRECTORY)
    set(COMPILED_RES_DIR_PATH "res-compiled/")

    string(REPLACE "/" "_" COMPILED_RES_NAME ${REL_RES_PATH})
    get_filename_component(RES_EXT ${COMPILED_RES_NAME} LAST_EXT)
    get_filename_component(COMPILED_RES_NAME_WLE ${COMPILED_RES_NAME} NAME_WLE)
    if(COMPILED_RES_NAME MATCHES "^values_.*\.xml$")
      set(COMPILED_RES_NAME "${COMPILED_RES_NAME_WLE}.arsc.flat")
    else()
      set(COMPILED_RES_NAME "${COMPILED_RES_NAME_WLE}${RES_EXT}.flat")
    endif()

    set(COMPILED_RES_PATH ${COMPILED_RES_DIR_PATH}/${COMPILED_RES_NAME})
    list(APPEND COMPILED_RESOURCES ${COMPILED_RES_PATH})

    file(TO_NATIVE_PATH ${RES_FILE} IN_NATIVE_PATH)
    file(TO_NATIVE_PATH ${COMPILED_RES_DIR_PATH} OUT_NATIVE_PATH)
    add_custom_command(
      OUTPUT ${COMPILED_RES_PATH}
      COMMAND ${ANDROID_AAPT2} compile -o "${OUT_NATIVE_PATH}" "${IN_NATIVE_PATH}"
      DEPENDS ${RES_FILE}
      COMMENT "aapt2: compile ${RES_FILE} => ${COMPILED_RES_PATH}"
    )
  endforeach()

  # Make path absolute
  if(NOT IS_ABSOLUTE ${APK_MANIFEST})
    file(REAL_PATH ${APK_MANIFEST} APK_MANIFEST BASE_DIRECTORY ${CMAKE_CURRENT_LIST_DIR})
  endif()

  # Fix resource paths
  foreach(RES ${COMPILED_RESOURCES})
    file(REAL_PATH ${RES} RES_NATIVE BASE_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR})
    list(APPEND RESOURCES_NATIVE ${RES_NATIVE})
  endforeach()
  file(TO_NATIVE_PATH "res-compiled" RES_PATH_NATIVE)

  # Link resources into apk
  set(RES_APK_PATH ${CMAKE_CURRENT_BINARY_DIR}/${APK_NAME}-res-unaligned.apk)
  file(TO_NATIVE_PATH ${APK_MANIFEST} MANIFEST_PATH_NATIVE)
  add_custom_command(
    OUTPUT ${RES_APK_PATH}
    DEPENDS ${APK_RES} ${APK_MANIFEST} ${COMPILED_RESOURCES}
    COMMAND ${ANDROID_AAPT2} link -o ${RES_APK_PATH} -I ${ANDROID_PLATFORM_PATH}/android.jar ${RESOURCES_NATIVE} --manifest ${MANIFEST_PATH_NATIVE}
    COMMENT "aapt2: link ${RES_APK_PATH}"
    USES_TERMINAL
  )

  set(APK_STAGING_PATH ${CMAKE_CURRENT_BINARY_DIR}/${APK_NAME}-apk-staging)

  # Prepare native libraries
  set(NATIVE_LIB_PATH "lib/${ANDROID_ABI}")

  # Create directories
  file(REMOVE_RECURSE  ${APK_STAGING_PATH})
  file(MAKE_DIRECTORY ${APK_STAGING_PATH}/${NATIVE_LIB_PATH})

  # Merge code and resources
  set(APK_PATH ${CMAKE_CURRENT_BINARY_DIR}/${APK_NAME}.unaligned.apk)
  foreach(LIB_TARGET ${APK_LIB_TARGETS})
    list(APPEND COPY_NATIVE_LIBS_COMMAND
      COMMAND ${CMAKE_COMMAND} -E copy_if_different $<TARGET_FILE:${LIB_TARGET}> ${NATIVE_LIB_PATH}
      DEPENDS ${LIB_TARGET}
    )
  endforeach()

  if(_ANDROID_DEBUG)
    # Store binaries uncompressed for faster iteration times
    set(ARCHIVE_CMDLINE ${SEVEN_ZIP} a -tzip -mm=copy ${APK_PATH} *)
  else()
    set(ARCHIVE_CMDLINE ${SEVEN_ZIP} a -tzip ${APK_PATH} *)
  endif()


  add_custom_command(
    OUTPUT ${APK_PATH}
    DEPENDS ${RES_APK_PATH} ${CLASSES_DEX_PATH}/classes.dex
    WORKING_DIRECTORY ${APK_STAGING_PATH}
    COMMAND ${CMAKE_COMMAND} -E copy_if_different ${CLASSES_DEX_PATH}/classes.dex ./
    ${COPY_NATIVE_LIBS_COMMAND}
    COMMAND ${CMAKE_COMMAND} -E copy_if_different ${RES_APK_PATH} ${APK_PATH}
    COMMAND ${ARCHIVE_CMDLINE}
    USES_TERMINAL
  )

  # zipalign
  set(ALIGNED_APK_PATH ${CMAKE_CURRENT_BINARY_DIR}/${APK_NAME}.aligned.apk)
  add_custom_command(
    OUTPUT ${ALIGNED_APK_PATH}
    DEPENDS ${APK_PATH}
    COMMAND ${CMAKE_COMMAND} -E rm -f ${ALIGNED_APK_PATH}
    COMMAND ${ANDROID_ZIPALIGN} 4 ${APK_PATH} ${ALIGNED_APK_PATH}
    USES_TERMINAL
  )

  # apksigner
  set(APK_PATH ${CMAKE_CURRENT_BINARY_DIR}/${APK_NAME}.apk)
  add_custom_command(
    OUTPUT ${APK_PATH}
    DEPENDS ${ALIGNED_APK_PATH}
    COMMAND ${Java_JAVA_EXECUTABLE} -jar ${ANDROID_APKSIGNER_JAR} sign --ks ${DEBUG_KEYSTORE_PATH} --ks-pass pass:${DEBUG_KEYSTORE_PASS} --out ${APK_PATH} ${ALIGNED_APK_PATH}
    USES_TERMINAL
  )

  add_custom_target(${APK_NAME}
    DEPENDS ${APK_PATH}
  )
endfunction()
