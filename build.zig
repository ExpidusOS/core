const std = @import("std");
const Build = @import("build");
const Pkgbuild = @import("pkgbuild");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const linkage = b.option(std.Build.Step.Compile.Linkage, "linkage", "whether to statically or dynamically link the library") orelse .static;
    const variant = b.option(Build.Variant, "variant", "System variant") orelse .core;
    const versionTag = b.option([]const u8, "version-tag", "Sets the version tag") orelse Build.runAllowFailSingleLine(b, &.{ "git", "rev-parse", "--abbrev-ref", "HEAD" }) orelse "0.2.0-alpha";
    const buildHash = b.option([]const u8, "build-hash", "Sets the build hash") orelse if (Build.runAllowFailSingleLine(b, &.{ "git", "rev-parse", "HEAD" })) |str| str[0..7] else "AAAAAAA";

    if (target.result.isGnuLibC()) {
        std.debug.panic("Target {s} is using glibc which is not supported at the moment.", .{target.result.zigTriple(b.allocator) catch @panic("OOM")});
    }

    const ziggybox = b.dependency("ziggybox", .{
        .target = target,
        .optimize = optimize,
        .linkage = linkage,
    });

    ziggybox.builder.resolveInstallPrefix(b.install_prefix, .{});
    b.getInstallStep().dependOn(&ziggybox.builder.install_tls.step);

    const acl = b.dependency("pkgs/acl", .{
        .target = target,
        .optimize = optimize,
        .linkage = linkage,
    });

    acl.builder.resolveInstallPrefix(b.install_prefix, .{});
    b.getInstallStep().dependOn(&acl.builder.install_tls.step);

    const files = b.addWriteFiles();

    b.getInstallStep().dependOn(&b.addInstallFileWithDir(files.add("etc/os-release", b.fmt(
        \\NAME="ExpidusOS"
        \\ID=expidus
        \\PRETTY_NAME="ExpidusOS {s} Willamette"
        \\VARIANT="{s}"
        \\VARIANT_ID={s}
        \\VERSION="Willamette {s}"
        \\VERSION_ID="{s}"
        \\BUILD_ID="{s}-{s}"
        \\HOME_URL=https://expidusos.com
        \\DOCUMENTATION_URL=https://wiki.expidusos.com
        \\BUG_REPORT_URL=https://github.com/ExpidusOS/core/issues
        \\ARCHITECTURE={s}
        \\DEFAULT_HOSTNAME=expidus-{s}
        \\
    , .{
        variant.name(),
        variant.name(),
        @tagName(variant),
        versionTag,
        versionTag,
        versionTag,
        buildHash,
        @tagName(target.result.cpu.arch),
        @tagName(variant),
    })), .prefix, "etc/os-release").step);
}
