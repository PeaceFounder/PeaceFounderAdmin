using AppBundler

import Pkg.BinaryPlatforms: Linux

APP_DIR = dirname(@__DIR__)

BUILD_DIR = joinpath(APP_DIR, "build")
mkpath(BUILD_DIR)

AppBundler.bundle_app(Linux(:x86_64), APP_DIR, "$BUILD_DIR/peacefounder-server-0.1.0-x64.snap")
AppBundler.bundle_app(Linux(:aarch64), APP_DIR, "$BUILD_DIR/peacefounder-server-0.1.0-arm64.snap")
