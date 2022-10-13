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
    this(CoreWireConfig config)
    {
        import std.exception : enforce;

        this.config = enforce(cast(FileCoreWireConfig)config);
    }

    ///
    override void downloadFile(string src, string dst) const
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
    override void uploadFile(string src, string dst) const
    {
        downloadFile(src, dst);
    }

    ///
    override bool canMkdir() const
    {
        return true;
    }

    ///
    override CoreWireType type() const
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
    ///
    bool allowSymLink;
}