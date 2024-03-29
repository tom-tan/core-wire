/**
 * Authors: Tomoya Tanjo
 * Copyright: © 2022 Tomoya Tanjo
 * License: Apache-2.0
 */
module wire.core.file;

import wire.core : CoreWire, CoreWireConfig, CoreWireType;

///
class FileCoreWire : CoreWire
{
    /**
     * Bugs: It does not capture the case of using symlinks when download but not using symlinks when upload
     */
    this(CoreWireConfig config) @safe
    {
        import std.exception : enforce;

        this.config = enforce(cast(FileCoreWireConfig)config);
    }

    ///
    override void downloadFile(string src, string dst) const @safe
    {
        import wire.util : path;

        auto srcPath = src.path;
        auto dstPath = dst.path;

        if (config.useSymLink)
        {
            import std.file : symlink;
            symlink(srcPath, dstPath);
        }
        else
        {
            import std.file : copy;
            copy(srcPath, dstPath);
        }
    }

    ///
    override void downloadDirectory(string src, string dst) const @safe
    {
        import wire.util : path;

        auto srcPath = src.path;
        auto dstPath = dst.path;
        if (config.useSymLink)
        {
            import std.file : symlink;
            symlink(srcPath, dstPath);
        }
        else
        {
            () @trusted // See_Also: https://github.com/dlang/phobos/blob/67d4521c2c53b4e8c4a5213860c49caf9396bde2/std/file.d#L4468
            {
            import std : dirEntries, DirEntry, mkdir, SpanMode;
            mkdir(dstPath);
            foreach(DirEntry e; dirEntries(srcPath, SpanMode.breadth, true))
            {
                import std : buildPath, relativePath;

                auto srcRelEntry = e.name.relativePath(srcPath);
                auto dstEntry = buildPath(dstPath, srcRelEntry);
                if (e.isFile)
                {
                    import std.file : copy;
                    copy(e.name, dstEntry);
                }
                else if (e.isDir)
                {
                    mkdir(dstEntry);
                }
                else if (e.isSymlink)
                {
                    import std : absolutePath, enforce, exists, format, isDir, isFile, readLink, startsWith;

                    auto resolved = e.name.readLink.absolutePath;
                    enforce(!srcPath.startsWith(resolved), "Recursive symlinks are not allowed");
                    enforce(resolved.exists, format!"`%s` does not exist (linked from `%s`)"(resolved, e.name));
                    if (resolved.isFile)
                    {
                        import std.file : copy;
                        copy(resolved, dstEntry);
                    }
                    else if (resolved.isDir)
                    {
                        downloadDirectory("file://"~resolved, "file://"~dstEntry);
                    }
                    else
                    {
                        throw new Exception("Unknown file type");
                    }
                }
            }
            }();
        }
    }

    ///
    override void uploadDirectory(string src, string dst) const @safe
    {
        downloadDirectory(src, dst);
    }

    ///
    override bool supportDownloadDirectory() const @safe
    {
        return true;
    }

    ///
    override CoreWireType type() const @safe
    {
        return CoreWireType.both;
    }

    ///
    FileCoreWireConfig config;

protected:
    override string[] schemes() const nothrow pure @safe
    {
        return ["file"];
    }
}

class FileCoreWireConfig : CoreWireConfig
{
    this(bool useSymLink) @nogc nothrow pure @safe
    {
        this.useSymLink = useSymLink;
    }

    ///
    bool useSymLink;
}

/// Download file with `useSymlink = false`
@safe unittest
{
    import std : buildPath, exists, isFile, mkdir, randomUUID, readText, rmdirRecurse, tempDir;
    import std.file : write; // not to conflict with std.stdio.write
    import wire.util : absoluteURI, path;

    enum fileName = "deleteme";
    enum contents = "This is an example text.\n";

    auto srcDir = buildPath(tempDir, randomUUID.toString);
    mkdir(srcDir);
    scope(exit) rmdirRecurse(srcDir);

    auto srcURI = buildPath(srcDir, fileName).absoluteURI;

    srcURI.path.write(contents);

    auto dstDir = buildPath(tempDir, randomUUID.toString);
    mkdir(dstDir);
    scope(exit) rmdirRecurse(dstDir);

    auto dstURI = buildPath(dstDir, fileName).absoluteURI;
    
    auto cw = new FileCoreWire(new FileCoreWireConfig(false));
    cw.downloadFile(srcURI, dstURI);

    assert(dstURI.path.exists);
    assert(dstURI.path.isFile);
    assert(dstURI.path.readText == contents);
}

/// Download file with `useSymlink = true`
@safe unittest
{
    import std : buildPath, exists, isFile, isSymlink, mkdir, randomUUID, readLink, readText, rmdirRecurse, tempDir;
    import std.file : write; // not to conflict with std.stdio.write
    import wire.util : absoluteURI, path;

    enum fileName = "deleteme";
    enum contents = "This is an example text.\n";

    auto srcDir = buildPath(tempDir, randomUUID.toString);
    mkdir(srcDir);
    scope(exit) rmdirRecurse(srcDir);

    auto srcURI = buildPath(srcDir, fileName).absoluteURI;

    srcURI.path.write(contents);

    auto dstDir = buildPath(tempDir, randomUUID.toString);
    mkdir(dstDir);
    scope(exit) rmdirRecurse(dstDir);

    auto dstURI = buildPath(dstDir, fileName).absoluteURI;
    
    auto cw = new FileCoreWire(new FileCoreWireConfig(true));
    cw.downloadFile(srcURI, dstURI);

    assert(dstURI.path.exists);
    assert(dstURI.path.isSymlink);
    assert(dstURI.path.readLink.isFile);
    assert(dstURI.path.readLink.readText == contents);
}

/// Download directory with `useSymlink = false`
@safe unittest
{
    import std : buildPath, exists, isDir, isFile, mkdir, randomUUID, readText, rmdirRecurse, tempDir;
    import std.file : write; // not to conflict with std.stdio.write
    import wire.util : absoluteURI, path;

    enum dirName = "deleteme";
    enum fileName = "deleteThisFile";
    enum contents = "This is an example text.\n";

    // building src directory
    auto srcDir = buildPath(tempDir, randomUUID.toString);
    mkdir(srcDir);
    scope(exit) rmdirRecurse(srcDir);

    auto srcURI = buildPath(srcDir, dirName).absoluteURI;
    mkdir(srcURI.path);
    buildPath(srcURI.path, fileName).write(contents);

    // generate dst base directory
    auto dstDir = buildPath(tempDir, randomUUID.toString);
    mkdir(dstDir);
    scope(exit) rmdirRecurse(dstDir);

    auto dstURI = buildPath(dstDir, dirName).absoluteURI;
    
    auto cw = new FileCoreWire(new FileCoreWireConfig(false));
    cw.downloadDirectory(srcURI, dstURI);

    // assertions
    assert(dstURI.path.exists);
    assert(dstURI.path.isDir);
    auto dirFilePath = buildPath(dstURI.path, fileName);
    assert(dirFilePath.exists);
    assert(dirFilePath.isFile);
    assert(dirFilePath.readText == contents);
}
