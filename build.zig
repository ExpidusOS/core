const std = @import("std");
const Build = @import("build");
const Pkgbuild = @import("pkgbuild");

pub const Variant = enum {
    core,
    devkit,
    mainline,
    bootstrap,

    pub fn name(self: Variant) []const u8 {
        return switch (self) {
            .core => "Core",
            .devkit => "DevKit",
            .mainline => "Mainline",
            .bootstrap => "Bootstrap",
        };
    }
};

pub const VendorMeta = struct {
    name: []const u8,
    url: []const u8,
};

fn fixupRpaths(b: *std.Build, cs: *std.Build.Step.Compile) void {
    for (cs.root_module.link_objects.items) |*link_obj| {
        if (link_obj.* == .other_step) {
            fixupRpaths(b, link_obj.other_step);

            if (link_obj.other_step.kind == .lib and link_obj.other_step.linkage == .dynamic) {
                for (link_obj.other_step.step.owner.getInstallStep().dependencies.items) |link_obj_dep_step| {
                    const inst = link_obj_dep_step.cast(std.Build.Step.InstallArtifact) orelse continue;
                    if (inst.artifact == link_obj.other_step) {
                        cs.step.dependOn(&inst.step);
                        break;
                    }
                }

                link_obj.* = .{
                    .static_path = .{
                        .path = b.getInstallPath(.lib, link_obj.other_step.out_lib_filename),
                    },
                };
            }
        }
    }
}

fn addPackage(b: *std.Build, name: []const u8, args: anytype) void {
    const pkgDep = b.dependency(b.fmt("pkgs/{s}", .{name}), args);

    pkgDep.builder.resolveInstallPrefix(b.install_prefix, .{});
    pkgDep.builder.install_tls.step.name = b.fmt("install {s}", .{name});
    b.getInstallStep().dependOn(&pkgDep.builder.install_tls.step);

    for (pkgDep.builder.install_tls.step.dependencies.items) |dep_step| {
        const inst = dep_step.cast(std.Build.Step.InstallArtifact) orelse continue;
        fixupRpaths(b, inst.artifact);
    }
}

fn access(path: []const u8, flags: std.fs.File.OpenFlags) bool {
    if (std.fs.path.isAbsolute(path)) {
        std.fs.accessAbsolute(path, flags) catch return false;
        return true;
    }

    std.fs.cwd().access(path, flags) catch return false;
    return true;
}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const linkage = b.option(std.builtin.LinkMode, "linkage", "whether to statically or dynamically link the library") orelse @as(std.builtin.LinkMode, if (target.result.isGnuLibC()) .dynamic else .static);
    const variant = b.option(Variant, "variant", "System variant") orelse .core;
    const versionTag = b.option([]const u8, "version-tag", "Sets the version tag") orelse Build.runAllowFailSingleLine(b, &.{ "git", "rev-parse", "--abbrev-ref", "HEAD" }) orelse "0.2.0-alpha";
    const buildHash = b.option([]const u8, "build-hash", "Sets the build hash") orelse if (Build.runAllowFailSingleLine(b, &.{ "git", "rev-parse", "HEAD" })) |str| str[0..7] else "AAAAAAA";
    const vendorPath = b.option([]const u8, "vendor", "Path to the vendor metadata and other files") orelse b.pathFromRoot("vendor/midstall");

    inline for (@as([]const []const u8, &.{
        "attr",
        "acl",
        "libaudit",
        "libcap-ng",
        "pcre2",
        "python",
        "expat",
        "selinux",
        "apparmor",
        "dbus",
        "ziggybox",
    })) |pkgName| {
        addPackage(b, pkgName, .{
            .target = target,
            .optimize = optimize,
            .linkage = linkage,
        });
    }

    addPackage(b, "runit", .{
        .target = target,
        .optimize = optimize,
    });

    const vendorMeta = blk: {
        const path = b.pathJoin(&.{ vendorPath, "meta.json" });

        var file = if (std.fs.path.isAbsolute(path)) try std.fs.openFileAbsolute(path, .{}) else try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const meta = try file.metadata();
        const str = try file.readToEndAlloc(b.allocator, meta.size());
        defer b.allocator.free(str);

        break :blk try std.json.parseFromSlice(VendorMeta, b.allocator, str, .{ .allocate = .alloc_always });
    };
    defer vendorMeta.deinit();

    const files = b.addWriteFiles();

    if (access(b.pathJoin(&.{ vendorPath, "logo.png" }), .{})) {
        b.getInstallStep().dependOn(&b.addInstallFileWithDir(files.addCopyFile(.{
            .path = b.pathJoin(&.{ vendorPath, "logo.png" }),
        }, "usr/share/icons/os-vendor-logo.png"), .prefix, "usr/share/icons/os-vendor-logo.png").step);
    }

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
        \\VENDOR_NAME="{s}"
        \\VENDOR_URL={s}
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
        vendorMeta.value.name,
        vendorMeta.value.url,
    })), .prefix, "etc/os-release").step);
}
