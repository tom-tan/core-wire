/**
 * Authors: Tomoya Tanjo
 * Copyright: © 2022 Tomoya Tanjo
 * License: Apache-2.0
 */
module wire.core.http;

import wire.core : CoreWire, CoreWireConfig, CoreWireType;

///
class HTTPCoreWire : CoreWire
{
    ///
    this(CoreWireConfig config = null) @safe
    {
    }

    ///
    override void downloadFile(string src, string dst) const @trusted
    {
        import wire.exception : ResourceError;
        import wire.util : path;
        import requests;

        import std : copy, File;

        auto rq = Request();
        rq.useStreaming = true;
        auto rs = rq.get(src);

        auto dstFile = File(dst.path, "w");
        rs.receiveAsRange()
          .copy(dstFile.lockingBinaryWriter);

        // TODO: handling ResourceEror such as no network connections etc.
    }

    ///
    override void uploadDirectory(string src, string dst) const @safe
    {
        assert(false, "Not yet implemented");
    }

    ///
    override bool supportDownloadDirectory() const @safe
    {
        return false;
    }

    ///
    override CoreWireType type() const @safe
    {
        return CoreWireType.down;
    }

protected:
    override const(string[]) schemes() const nothrow pure @safe
    {
        return ["http", "https"];
    }
}
