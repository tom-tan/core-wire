/**
 * Authors: Tomoya Tanjo
 * Copyright: © 2022 Tomoya Tanjo
 * License: Apache-2.0
 */
module wire;

import std.file : exists, isFile;

import wire.core : CoreWire, CoreWireType;
import wire.exception : WireException;
import wire.util : path, scheme;

///
class Wire
{
    ///
    void addCoreWire(string scheme, CoreWire coreWire, CoreWireType type = CoreWireType.both)
    {
        import std.exception : enforce;
        import std.format : format;

        enforce!WireException(
            coreWire.canSupport(scheme),
            format!"`%s` is not supported by `%s`"(scheme, coreWire),
        );

        auto t = coreWire.type & type;
        enforce!WireException(t != CoreWireType.none);

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
    void removeCoreWire(string scheme, CoreWireType type = CoreWireType.both)
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
    void downloadFile(string src, string dst) const
    in(dst.scheme == "file")
    out(;dst.path.exists && dst.path.isFile)
    {
        import std.exception : enforce;
        import std.format : format;

        auto srcScheme = src.scheme;
        auto dl = enforce!WireException(
            srcScheme in downloader,
            format!"Core wire for scheme `%s` not found"(srcScheme),
        );
        dl.downloadFile(src, dst);
    }

    ///
    void uploadFile(string src, string dst) const
    in(src.scheme == "file")
    in(src.path.exists && src.path.isFile)
    {
        import std.exception : enforce;
        import std.format : format;

        auto dstScheme = dst.scheme;
        auto ul = enforce!WireException(
            dstScheme in uploader,
            format!"Core wire for scheme `%s` not found"(dstScheme),
        );
        ul.downloadFile(src, dst);
    }
private:
    CoreWire[string] downloader, uploader;
}
