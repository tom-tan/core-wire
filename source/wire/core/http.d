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
    override void downloadFile(string src, string dst) const
    {
        import wire.exception : ResourceError;
        import wire.util : path;
        import std : enforce, execute, format;

        auto ret = execute(["curl", "-f", src, "-o", dst.path]);
        enforce!ResourceError(
            ret.status == 0,
            format!"Download `%s` failed with the following message: `%s`"(src, ret.output)
        );
    }

    ///
    override void uploadDirectory(string src, string dst) const @safe
    {
        downloadDirectory(src, dst);
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
    override string[] schemes() const nothrow pure @safe
    {
        return ["http", "https"];
    }
}
