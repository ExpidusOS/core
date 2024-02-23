const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const linkage = b.option(std.Build.Step.Compile.Linkage, "linkage", "whether to statically or dynamically link the library") orelse .static;
    const tools = b.option([]const []const u8, "tools", "The tools to build") orelse &[_][]const u8{
        "attr",
        "getfattr",
        "setfattr",
    };

    const source = b.dependency("attr", .{});

    const configHeader = b.addConfigHeader(.{}, .{
        .HAVE_ALLOCA = 1,
        .HAVE_DCGETTEXT = 1,
        .HAVE_DLFCN_H = 1,
        .HAVE_GETEXT = 1,
        .HAVE_ICONV = 1,
        .HAVE_INTTYPES_H = 1,
        .HAVE_LIBATTR = 1,
        .HAVE_MINIX_CONFIG_H = null,
        .HAVE_STDINT_H = 1,
        .HAVE_STDIO_H = 1,
        .HAVE_STDLIB_H = 1,
        .HAVE_STRINGS_H = null,
        .HAVE_STRING_H = 1,
        .HAVE_SYS_STAT_H = 1,
        .HAVE_SYS_TYPES_H = 1,
        .HAVE_UNISTD_H = 1,
        .HAVE_WCHAR_H = 1,
        .SYSCONFDIR = "/etc",
        .EXPORT = {},
        .VERSION = "2.5.2",
        ._POSIX_SOURCE = 1,
        ._GNU_SOURCE = 1,
    });

    const headers = b.addWriteFiles();
    _ = headers.addCopyFile(source.path("include/attributes.h"), "attr/attributes.h");
    _ = headers.addCopyFile(source.path("include/error_context.h"), "attr/error_context.h");
    _ = headers.addCopyFile(source.path("include/libattr.h"), "attr/libattr.h");

    const lib = std.Build.Step.Compile.create(b, .{
        .name = "attr",
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
            .patch = 2502,
        },
    });

    lib.expect_errors = .{ .contains = "" };
    lib.version_script = source.path("exports");

    lib.addIncludePath(source.path("include"));
    lib.addIncludePath(headers.getDirectory());
    lib.addConfigHeader(configHeader);

    {
        var dir = try std.fs.openDirAbsolute(source.path("libattr").getPath(b), .{ .iterate = true });
        defer dir.close();

        var walk = try dir.walk(b.allocator);
        defer walk.deinit();

        while (try walk.next()) |entry| {
            if (entry.kind != .file or !std.mem.endsWith(u8, entry.basename, ".c")) continue;

            lib.addCSourceFile(.{
                .file = source.path(b.pathJoin(&.{ "libattr", entry.path })),
            });
        }
    }

    lib.installHeadersDirectoryOptions(.{
        .source_dir = headers.getDirectory(),
        .install_dir = .header,
        .install_subdir = "",
    });

    b.installArtifact(lib);

    const libmisc = b.addStaticLibrary(.{
        .name = "misc",
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    libmisc.addIncludePath(source.path("include"));
    libmisc.addConfigHeader(configHeader);

    libmisc.addCSourceFiles(.{
        .files = &.{
            source.path("libmisc/high_water_alloc.c").getPath(b),
            source.path("libmisc/next_line.c").getPath(b),
            source.path("libmisc/quote.c").getPath(b),
            source.path("libmisc/unquote.c").getPath(b),
            source.path("libmisc/walk_tree.c").getPath(b),
        },
    });

    for (tools) |tool| {
        const exec = b.addExecutable(.{
            .name = tool,
            .target = target,
            .optimize = optimize,
            .linkage = linkage,
            .link_libc = true,
        });

        exec.addConfigHeader(configHeader);
        exec.addIncludePath(source.path("include"));

        exec.linkLibrary(lib);
        exec.linkLibrary(libmisc);

        exec.addCSourceFile(.{ .file = source.path(b.fmt("tools/{s}.c", .{tool})) });
        b.installArtifact(exec);
    }

    b.getInstallStep().dependOn(&b.addInstallFile(source.path("xattr.conf"), "etc/xattr.conf").step);
}
