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
        if (config.allowSymLink)
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
        if (config.allowSymLink)
        {
            import std.file : symlink;
            symlink(srcPath, dstPath);
        }
        else
        {
            () @trusted
            {
            import std : baseName, buildPath, dirEntries, DirEntry, mkdir, SpanMode;
            auto destDirName = buildPath(dstPath, srcPath.baseName);
            mkdir(destDirName);
            foreach(DirEntry e; dirEntries(srcPath, SpanMode.depth, true))
            {
                import std : stderr;
                if (e.isFile)
                {
                    stderr.writefln!"copy file `%s` to `%s`"(e.name, destDirName);
                    //copy(e.name, destDirName);
                }
                else if (e.isDir)
                {
                    stderr.writefln!"mkdir `%s` to `%s`"(e.name, destDirName);
                    // mkdirRecurse(buildPath(destDirName, e.name))?
                }
                else if (e.isSymlink)
                {
                    stderr.writefln!"`%s` is symlink. how to deal with it?"(e.name);
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
    override CoreWireType type() const @safe
    {
        return CoreWireType.both;
    }

protected:
    override string[] schemes() const nothrow pure @safe
    {
        return ["file"];
    }

    FileCoreWireConfig config;
}

class FileCoreWireConfig : CoreWireConfig
{
    this(bool allowSymLink)
    {
        this.allowSymLink = allowSymLink;
    }

    ///
    bool allowSymLink;
}

/// case of `allowSymlink = false`
unittest
{
    import std : buildPath, exists, isFile, mkdir, randomUUID, readText, rmdirRecurse, tempDir, stderr;
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

/// case of `allowSymlink = true`
unittest
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


///
unittest
{
    // mk tmpdir
    // scope(exit) rm
    // mk tmpdir
    // dl dir
    // verify
}
