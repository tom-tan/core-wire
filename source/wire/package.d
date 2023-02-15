/**
 * Authors: Tomoya Tanjo
 * Copyright: © 2022 Tomoya Tanjo
 * License: Apache-2.0
 */
module wire;

import std.file : exists, isFile;

import wire.core : CoreWire, CoreWireType;
import wire.exception : UnsupportedScheme;
import wire.util : path, scheme;

///
Wire defaultWire;

static this()
{
    import wire.core.file : FileCoreWire, FileCoreWireConfig;
    defaultWire = new Wire;
    defaultWire.addCoreWire("file", new FileCoreWire(new FileCoreWireConfig(false)), CoreWireType.down);
}

///
class Wire
{
    ///
    void addCoreWire(string scheme, CoreWire coreWire, CoreWireType type = CoreWireType.both) @safe
    {
        import std.exception : enforce;
        import std.format : format;

        enforce!UnsupportedScheme(
            coreWire.canSupport(scheme),
            () @trusted { return format!"`%s` is not supported by `%s`"(scheme, coreWire); }(),
        );

        auto t = coreWire.type & type;
        enforce!UnsupportedScheme(t != CoreWireType.none);

        if (t & CoreWireType.up)
        {
            uploader[scheme] = coreWire;
        }
        if (t & CoreWireType.down)
        {
            downloader[scheme] = coreWire;
        }
    }

    ///
    void removeCoreWire(string scheme, CoreWireType type = CoreWireType.both) @safe
    {
        if (type & CoreWireType.up)
        {
            uploader.remove(scheme);
        }
        if (type & CoreWireType.down)
        {
            downloader.remove(scheme);
        }
    }

    ///
    void downloadFile(string src, string dst) const @safe
    in(dst.scheme == "file")
    out(;dst.path.exists && dst.path.isFile)
    {
        import std.exception : enforce;
        import std.format : format;

        auto srcScheme = src.scheme;
        auto dl = enforce!UnsupportedScheme(
            srcScheme in downloader,
            format!"Core wire for scheme `%s` not found"(srcScheme),
        );
        dl.downloadFile(src, dst);
    }

    ///
    void downloadDirectory(string src, string dst) const @safe
    {
        import std.exception : enforce;
        import std.format : format;

        auto srcScheme = src.scheme;
        auto dl = enforce!UnsupportedScheme(
            srcScheme in downloader,
            format!"Core wire for scheme `%s` not found"(srcScheme),
        );
        dl.downloadDirectory(src, dst);
    }

    ///
    void uploadDirectory(string src, string dst) const @safe
    in(src.scheme == "file")
    in(src.path.exists && src.path.isFile)
    {
        import std.exception : enforce;
        import std.format : format;

        auto dstScheme = dst.scheme;
        auto ul = enforce!UnsupportedScheme(
            dstScheme in uploader,
            format!"Core wire for scheme `%s` not found"(dstScheme),
        );
        ul.uploadDirectory(src, dst);
    }
private:
    CoreWire[string] downloader, uploader;
}
