const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const linkage = b.option(std.Build.Step.Compile.Linkage, "linkage", "whether to statically or dynamically link the library") orelse .static;

    const source = b.dependency("acl", .{});

    const attr = b.dependency("attr", .{
        .target = target,
        .optimize = optimize,
        .linkage = linkage,
    });

    const configHeader = b.addConfigHeader(.{}, .{
        .ENABLE_NLS = 1,
        .HAVE_ATTR_ERROR_CONTEXT_H = 1,
        .HAVE_LIBACL_LIBACL_H = 1,
        .HAVE_ACL_LIBACL_H = 1,
        .HAVE_ACL_ENTRIES = 1,
        .HAVE_ACL_GET_ENTRY = 1,
        .HAVE_ACL_FREE = 1,
        .HAVE_DCGETTEXT = null,
        .HAVE_DLFCN_H = 1,
        .HAVE_GETTEXT = null,
        .HAVE_ICONV = 1,
        .HAVE_INTTYPES_H = 1,
        .HAVE_LIBATTR = 1,
        .HAVE_MINIX_CONFIG_H = null,
        .HAVE_STDINT_H = 1,
        .HAVE_STDIO_H = 1,
        .HAVE_STDLIB_H = 1,
        .HAVE_STRINGS_H = null,
        .HAVE_STRING_H = 1,
        .HAVE_SYS_ACL_H = 1,
        .HAVE_SYS_STAT_H = 1,
        .HAVE_SYS_TYPES_H = 1,
        .HAVE_UNISTD_H = 1,
        .HAVE_WCHAR_H = 1,
        .EXPORT = {},
    });

    const headers = b.addWriteFiles();
    _ = headers.addCopyFile(source.path("include/acl.h"), "sys/acl.h");
    _ = headers.addCopyFile(source.path("include/libacl.h"), "acl/libacl.h");

    const lib = std.Build.Step.Compile.create(b, .{
        .name = "acl",
        .root_module = .{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        },
        .kind = .lib,
        .linkage = linkage,
        .version = .{
            .major = 1,
            .minor = 1,
            .patch = 2302,
        },
    });

    lib.root_module.c_macros.append(b.allocator, "-DHAVE_CONFIG_H") catch @panic("OOM");

    lib.linkLibrary(blk: {
        for (attr.builder.install_tls.step.dependencies.items) |dep_step| {
            const inst = dep_step.cast(std.Build.Step.InstallArtifact) orelse continue;
            if (std.mem.eql(u8, inst.artifact.name, "attr") and inst.artifact.kind == .lib) {
                break :blk inst.artifact;
            }
        }

        unreachable;
    });

    lib.addIncludePath(source.path("include"));
    lib.addIncludePath(headers.getDirectory());
    lib.addConfigHeader(configHeader);

    {
        var dir = try std.fs.openDirAbsolute(source.path("libacl").getPath(b), .{ .iterate = true });
        defer dir.close();

        var walk = try dir.walk(b.allocator);
        defer walk.deinit();

        while (try walk.next()) |entry| {
            if (entry.kind != .file or !std.mem.endsWith(u8, entry.basename, ".c")) continue;

            lib.addCSourceFile(.{
                .file = source.path(b.pathJoin(&.{ "libacl", entry.path })),
            });
        }
    }

    lib.installHeadersDirectoryOptions(.{
        .source_dir = headers.getDirectory(),
        .install_dir = .header,
        .install_subdir = "",
    });

    b.installArtifact(lib);
}
