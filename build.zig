const std = @import("std");

pub const Variant = enum {
    core,

    pub fn name(self: Variant) []const u8 {
        return switch (self) {
            .core => "Core",
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
    const target = b.standardTargetOptions(.{
        .whitelist = &.{
            .{
                .cpu_arch = .aarch64,
                .os_tag = .linux,
                .abi = .gnu,
            },
            .{
                .cpu_arch = .aarch64,
                .os_tag = .linux,
                .abi = .musl,
            },
            .{
                .cpu_arch = .x86_64,
                .os_tag = .linux,
                .abi = .gnu,
            },
            .{
                .cpu_arch = .x86_64,
                .os_tag = .linux,
                .abi = .musl,
            },
            .{
                .cpu_arch = .riscv64,
                .os_tag = .linux,
                .abi = .gnu,
            },
            .{
                .cpu_arch = .riscv64,
                .os_tag = .linux,
                .abi = .musl,
            },
        },
    });

    const optimize = b.standardOptimizeOption(.{});
    const variant = b.option(Variant, "variant", "System variant") orelse .core;
    const versionTag = b.option([]const u8, "version-tag", "Sets the version tag") orelse runAllowFail(b, &.{ "git", "rev-parse", "--abbrev-ref", "HEAD" }) orelse "0.2.0-alpha";
    const buildHash = b.option([]const u8, "build-hash", "Sets the build hash") orelse if (runAllowFail(b, &.{ "git", "rev-parse", "HEAD" })) |str| str[0..7] else "AAAAAAA";

    const ziggybox = b.dependency("ziggybox", .{
        .target = target,
        .optimize = optimize,
    });

    for (ziggybox.builder.install_tls.step.dependencies.items) |dep_step| {
        const inst = dep_step.cast(std.Build.Step.InstallArtifact) orelse continue;
        b.installArtifact(inst.artifact);
    }

    const runit = b.dependency("runit", .{
        .target = target,
        .optimize = optimize,
    });

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
