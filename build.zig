const std = @import("std");

pub const Variant = enum {
    core,
    devkit,
    mainline,

    pub fn name(self: Variant) []const u8 {
        return switch (self) {
            .core => "Core",
            .devkit => "DevKit",
            .mainline => "Mainline",
        };
    }
};

fn runAllowFail(b: *std.Build, argv: []const []const u8) ?[]const u8 {
    var c: u8 = 0;
    if (b.runAllowFail(argv, &c, .Ignore) catch null) |result| {
        const end = std.mem.indexOf(u8, result, "\n") orelse result.len;
        return result[0..end];
    }
    return null;
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const linkage = b.option(std.Build.Step.Compile.Linkage, "linkage", "whether to statically or dynamically link the library") orelse .static;
    const variant = b.option(Variant, "variant", "System variant") orelse .core;
    const versionTag = b.option([]const u8, "version-tag", "Sets the version tag") orelse runAllowFail(b, &.{ "git", "rev-parse", "--abbrev-ref", "HEAD" }) orelse "0.2.0-alpha";
    const buildHash = b.option([]const u8, "build-hash", "Sets the build hash") orelse if (runAllowFail(b, &.{ "git", "rev-parse", "HEAD" })) |str| str[0..7] else "AAAAAAA";

    if (target.result.isGnuLibC()) {
        std.debug.panic("Target {s} is using glibc which is not supported at the moment.", .{target.result.zigTriple(b.allocator) catch @panic("OOM")});
    }

    const ziggybox = b.dependency("ziggybox", .{
        .target = target,
        .optimize = optimize,
        .linkage = linkage,
    });

    for (ziggybox.builder.install_tls.step.dependencies.items) |dep_step| {
        const inst = dep_step.cast(std.Build.Step.InstallArtifact) orelse continue;
        b.installArtifact(inst.artifact);
    }

    const runit = b.dependency("runit", .{
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(runit.artifact("runsv"));
    b.installArtifact(runit.artifact("runsvctrl"));
    b.installArtifact(runit.artifact("runsvdir"));
    b.installArtifact(runit.artifact("runsvstat"));
    b.installArtifact(runit.artifact("sv"));

    b.getInstallStep().dependOn(&b.addInstallArtifact(runit.artifact("runit"), .{
        .dest_dir = .{
            .override = .{
                .custom = "sbin",
            },
        },
    }).step);

    b.getInstallStep().dependOn(&b.addInstallArtifact(runit.artifact("runit-init"), .{
        .dest_dir = .{
            .override = .{
                .custom = "sbin",
            },
        },
    }).step);

    const dbus = b.dependency("dbus", .{
        .target = target,
        .optimize = optimize,
        .linkage = linkage,
    });

    if (linkage == .dynamic) b.installArtifact(dbus.artifact("dbus-1"));
    b.installArtifact(dbus.artifact("dbus-daemon"));

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
